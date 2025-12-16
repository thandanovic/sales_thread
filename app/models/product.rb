class Product < ApplicationRecord
  include Discard::Model

  belongs_to :shop
  belongs_to :olx_category_template, optional: true

  # ActiveStorage for images
  has_many_attached :images

  # OLX integration
  has_one :olx_listing, dependent: :destroy

  # Import tracking
  has_many :imported_products, dependent: :destroy

  # Enums
  enum :source, { csv: 'csv', intercars: 'intercars', olx: 'olx' }, validate: true

  # Validations
  validates :title, presence: true
  validates :source, presence: true
  validates :currency, inclusion: { in: %w[BAM EUR USD] }, allow_nil: true

  # Scopes
  scope :published, -> { where(published: true) }
  scope :unpublished, -> { where(published: false) }
  scope :by_source, ->(source) { where(source: source) }

  # Default scope to exclude discarded products
  default_scope -> { kept }

  # Callbacks
  before_save :calculate_final_price
  after_initialize :set_defaults, if: :new_record?

  ##
  # Publish product to OLX
  # Creates a new listing, updates existing one, or reconnects to a previously disconnected listing
  #
  # @return [OlxListing] The created/updated listing
  #
  def publish_to_olx
    service = OlxListingService.new(self)

    if olx_listing&.external_listing_id.present?
      # Update existing listing
      service.update_listing(olx_listing)
    elsif olx_external_id.present?
      # Reconnect to previously disconnected listing
      service.reconnect_listing(olx_external_id)
    else
      # Create new listing
      service.create_listing
    end
  end

  ##
  # Publish product to OLX and immediately publish it (not draft)
  #
  # @return [OlxListing] The published listing
  #
  def publish_to_olx!
    listing = publish_to_olx
    OlxListingService.new(self).publish_listing(listing)
  end

  ##
  # Unpublish product from OLX
  #
  # @return [OlxListing, nil] The unpublished listing or nil if not published
  #
  def unpublish_from_olx
    return nil unless olx_listing&.external_listing_id.present?

    service = OlxListingService.new(self)
    service.unpublish_listing(olx_listing)
  end

  ##
  # Remove listing from OLX completely
  #
  # @return [Boolean] true if successful
  #
  def remove_from_olx
    return false unless olx_listing&.external_listing_id.present?

    service = OlxListingService.new(self)
    service.delete_listing(olx_listing)
  end

  ##
  # Check if product is published on OLX
  #
  # @return [Boolean]
  #
  def published_on_olx?
    olx_listing&.published? || false
  end

  ##
  # Check if product has OLX listing (draft or published)
  #
  # @return [Boolean]
  #
  def has_olx_listing?
    olx_listing&.external_listing_id.present?
  end

  ##
  # Generate OLX title from template
  # Uses the template's title_template if available, otherwise uses product title
  #
  # @return [String] The generated title
  #
  def generate_olx_title
    return title unless olx_category_template&.title_template.present?

    template = olx_category_template.title_template

    # Replace placeholders with actual values
    # Match word characters including Unicode (for special chars like đ, č, š, ž, ć)
    template.gsub(/\{([^\}]+)\}/) do |match|
      placeholder = $1
      case placeholder.downcase
      when 'brand'
        brand.to_s  # Product brand field (short code like "ZOCW")
      when 'brend'
        # Extract from specs (full brand name like "CROSSWIND")
        extract_spec_value('Brend') || brand.to_s
      when 'title', 'naslov'
        title.to_s
      when 'sub_title', 'subtitle', 'podnaslov'
        sub_title.to_s  # Product subtitle/category from Intercars B2BName
      when 'sku', 'sifra'
        sku.to_s
      when 'category', 'kategorija'
        category.to_s
      when 'price', 'cijena', 'cena'
        final_price.present? ? "#{final_price} #{currency}" : price.to_s
      when 'technical_description', 'tehnicki_opis'
        technical_description.to_s
      when 'models', 'modeli', 'odgovara'
        models.to_s
      else
        # Try to extract from specs using the placeholder as a spec key
        # Supports both snake_case and exact matches
        # e.g., {proizvodac_akumulatora} matches "Proizvođač akumulatora"
        # e.g., {proizvođač_akumulatora} matches "Proizvođač akumulatora"
        # e.g., {tip} matches "Tip"
        extract_spec_by_placeholder(placeholder) || match
      end
    end
  end

  ##
  # Generate OLX description from template or filtered product data
  #
  # Priority:
  # 1. Use description_template if defined (with placeholder replacement)
  # 2. Use description_filter to filter existing description
  # 3. Fall back to raw description
  #
  # @return [String] The generated description
  #
  def generate_olx_description
    # Priority 1: Use description_template if defined
    if olx_category_template&.description_template.present?
      return generate_description_from_template
    end

    # Priority 2: Use description_filter if defined
    if olx_category_template&.description_filter.present?
      return filter_description_by_template
    end

    # Priority 3: Return raw description
    description
  end

  ##
  # Generate description from template using placeholder replacement
  #
  # @return [String] The generated description
  #
  def generate_description_from_template
    template = olx_category_template.description_template

    # Replace placeholders with actual values
    template.gsub(/\{([^\}]+)\}/) do |match|
      placeholder = $1
      case placeholder.downcase
      when 'brand', 'brend'
        brand.to_s
      when 'title', 'naslov'
        title.to_s
      when 'sub_title', 'subtitle', 'podnaslov'
        sub_title.to_s
      when 'sku', 'sifra'
        sku.to_s
      when 'category', 'kategorija'
        category.to_s
      when 'price', 'cijena', 'cena'
        final_price.present? ? "#{final_price} #{currency}" : price.to_s
      when 'technical_description', 'tehnicki_opis'
        technical_description.to_s
      when 'models', 'modeli', 'odgovara'
        models.to_s
      when 'description', 'opis'
        # Apply description_filter if defined, otherwise use raw description
        filter_description_by_template
      else
        # Try to extract from specs using the placeholder as a spec key
        extract_spec_by_placeholder(placeholder) || match
      end
    end
  end

  ##
  # Filter description using description_filter from template
  #
  # @return [String] The filtered description
  #
  def filter_description_by_template
    return description unless description.present?

    allowed_fields = olx_category_template.description_filter.reject(&:blank?)
    return description if allowed_fields.empty?

    filtered_parts = []

    # Check if description uses comma-separated format (single line) or line-separated format
    if description.include?(', ') && !description.include?("\n")
      # Comma-separated format: "Attr1: val1, Attr2: val2, ..."
      parts = description.split(', ').map(&:strip)

      parts.each do |part|
        next if part.blank?

        # Check if this part matches any allowed field
        part_matched = false
        allowed_fields.each do |field|
          break if part_matched

          patterns = field_to_patterns(field)
          patterns.each do |pattern|
            if part.match?(/^#{Regexp.escape(pattern)}\s*:/i)
              filtered_parts << part
              part_matched = true
              break
            end
          end
        end
      end

      result = filtered_parts.join(', ')
    else
      # Line-separated format: multiple lines
      filtered_lines = []

      description.split("\n").each do |line|
        line = line.strip
        next if line.blank?

        # Check if this line matches any allowed field
        line_matched = false
        allowed_fields.each do |field|
          break if line_matched

          patterns = field_to_patterns(field)
          patterns.each do |pattern|
            if line.match?(/#{Regexp.escape(pattern)}/i)
              filtered_lines << line
              line_matched = true
              break
            end
          end
        end
      end

      # Add SKU and Brand if they're in the filter and not already in filtered lines
      if allowed_fields.include?('sku') && sku.present?
        sku_line = "SKU: #{sku}"
        filtered_lines << sku_line unless filtered_lines.any? { |l| l.include?("SKU:") }
      end

      if allowed_fields.include?('brand') && brand.present?
        brand_line = "Brand: #{brand}"
        filtered_lines << brand_line unless filtered_lines.any? { |l| l.match?(/Brand:|Brend:/i) }
      end

      result = filtered_lines.join("\n")
    end

    result.present? ? result : description
  end

  ##
  # Auto-populate olx_title and olx_description before publishing
  # This should be called before creating/updating OLX listings
  # Only generates for non-OLX products (CSV/Intercars imports) when template is attached
  #
  def auto_populate_olx_fields
    # Skip auto-generation for products synced from OLX - they already have their original content
    return if source == 'olx'

    # Only generate if template is attached
    return unless olx_category_template.present?

    self.olx_title = generate_olx_title
    self.olx_description = generate_olx_description
  end

  ##
  # Generate preview of OLX attributes that will be sent
  # Returns array of hashes with name, value, and status (resolved/missing)
  #
  # @return [Array<Hash>] Array of attribute previews
  #
  def preview_olx_attributes
    return [] unless olx_category_template.present?

    service = OlxListingService.new(self)
    attributes = service.send(:build_category_attributes)

    # Get category attribute definitions for names
    category_attrs = olx_category_template.olx_category.olx_category_attributes

    previews = []

    # First add resolved attributes
    attributes.each do |attr|
      attr_def = category_attrs.find { |a| a.external_id == attr[:id] }
      previews << {
        id: attr[:id],
        name: attr_def&.name || "Unknown (#{attr[:id]})",
        value: attr[:value],
        required: attr_def&.required || false,
        status: 'resolved'
      }
    end

    # Then add missing required attributes
    category_attrs.where(required: true).each do |attr_def|
      next if previews.any? { |p| p[:id] == attr_def.external_id }
      previews << {
        id: attr_def.external_id,
        name: attr_def.name,
        value: nil,
        required: true,
        status: 'missing'
      }
    end

    previews.sort_by { |p| [p[:status] == 'missing' ? 0 : 1, p[:name]] }
  end

  ##
  # Extract a value from the specs JSON by key name
  #
  # @param key [String] The spec key to extract
  # @return [String, nil] The spec value or nil
  #
  def extract_spec_value(key)
    return nil unless specs.present?

    specs_hash = JSON.parse(specs) rescue {}
    specs_hash[key]
  end

  ##
  # Extract a spec value using a placeholder string
  # Converts snake_case placeholders to match actual spec keys
  #
  # @param placeholder [String] The placeholder string (e.g., "proizvodac_akumulatora")
  # @return [String, nil] The spec value or nil
  #
  def extract_spec_by_placeholder(placeholder)
    return nil unless specs.present?

    specs_hash = JSON.parse(specs) rescue {}
    return nil if specs_hash.empty?

    # Try exact match first (case-insensitive)
    exact_match = specs_hash.keys.find { |k| k.downcase == placeholder.downcase }
    return specs_hash[exact_match] if exact_match

    # Try normalized match: convert snake_case to title case
    # e.g., "proizvodac_akumulatora" → "Proizvođač akumulatora"
    normalized = normalize_placeholder(placeholder)

    # Find matching spec key
    matched_key = specs_hash.keys.find do |key|
      # Remove special characters and compare
      normalize_spec_key(key) == normalized
    end

    specs_hash[matched_key] if matched_key
  end

  private

  ##
  # Normalize a placeholder for matching against spec keys
  # Converts snake_case to space-separated lowercase and removes special characters
  #
  def normalize_placeholder(placeholder)
    # First replace underscores with spaces
    normalized = placeholder.gsub('_', ' ')

    # Remove accents and special characters
    normalized.gsub(/[čćžšđ]/i, {
      'č' => 'c', 'Č' => 'c',
      'ć' => 'c', 'Ć' => 'c',
      'ž' => 'z', 'Ž' => 'z',
      'š' => 's', 'Š' => 's',
      'đ' => 'd', 'Đ' => 'd'
    }).downcase
  end

  ##
  # Normalize a spec key for comparison
  # Removes special characters and converts to lowercase
  #
  def normalize_spec_key(key)
    # Remove accents and special characters, convert to lowercase
    key.gsub(/[čćžšđ]/i, {
      'č' => 'c', 'Č' => 'c',
      'ć' => 'c', 'Ć' => 'c',
      'ž' => 'z', 'Ž' => 'z',
      'š' => 's', 'Š' => 's',
      'đ' => 'd', 'Đ' => 'd'
    }).downcase
  end

  def field_to_patterns(field)
    field_map = {
      'namjena' => ['Namjena'],
      'sirina' => ['Širina', 'Sirina'],
      'profil' => ['Profil'],
      'promjer' => ['Promjer', 'Prečnik'],
      'sezona' => ['Sezona'],
      'klasa' => ['Klasa'],
      'brend' => ['Brend', 'Brand'],
      'profil_gume' => ['Profil gume'],
      'index_nosivosti' => ['Index nosivosti', 'Indeks nosivosti'],
      'indeks_brzine' => ['Indeks brzine'],
      'indeks_potrosnje' => ['Indeks potrošnje', 'Indeks potrosnje'],
      'indeks_prianjanja' => ['Indeks prianjanja'],
      'klasa_buke' => ['Klasa razine buke', 'Klasa buke'],
      'razine_buke' => ['Razine buke'],
      'klasa_guma' => ['Klasa guma'],
      'prianjanje_snijeg' => ['Prianjanje na snijegu', 'Prianjanje na sneg'],
      'prianjanje_led' => ['Prianjanje na ledu'],
      'tip_konstrukcija' => ['Tip (konstrukcija)', 'Tip'],
      'zracnica' => ['Zračnica', 'Zracnica'],
      'zastitni_naplatak' => ['Zaštitni naplatak', 'Zastitni naplatak'],
      'tip_zastitnog_naplatka' => ['Tip zaštitnog naplatka', 'Tip zastitnog naplatka'],
      'primjena_osovina' => ['Primjena na osovinu'],
      'stari_dot' => ['Stari DOT'],
      'oznaka_ms' => ['Oznaka M+S', 'M+S'],
      'vrsta_gume' => ['Vrsta gume'],
      'sifra_proizvodaca' => ['Šifra proizvođača', 'Sifra proizvodaca'],
      'ean' => ['EAN', 'EAN bar-kod'],
      'velicina' => ['Veličina', 'Velicina'],
      'tezina' => ['Težina', 'Tezina'],
      'sku' => ['SKU'],
      'brand' => ['Brand', 'Brend']
    }

    field_map[field] || [field.titleize]
  end

  def set_defaults
    self.currency ||= 'BAM'
    self.stock ||= 0
    self.published ||= false
    self.price ||= 0.0
    self.margin ||= 0.0
  end

  def calculate_final_price
    # Calculate final_price = price * (1 + margin/100)
    base_price = price || 0.0
    margin_percentage = margin || 0.0
    # Always round to nearest whole number (no cents)
    self.final_price = (base_price * (1 + margin_percentage / 100.0)).round(0)
  end
end
