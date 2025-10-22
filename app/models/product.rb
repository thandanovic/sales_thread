class Product < ApplicationRecord
  belongs_to :shop
  belongs_to :olx_category_template, optional: true

  # ActiveStorage for images
  has_many_attached :images

  # OLX integration
  has_one :olx_listing, dependent: :destroy

  # Import tracking
  has_many :imported_products, dependent: :destroy

  # Enums
  enum :source, { csv: 'csv', intercars: 'intercars' }, validate: true

  # Validations
  validates :title, presence: true
  validates :source, presence: true
  validates :currency, inclusion: { in: %w[BAM EUR USD] }, allow_nil: true

  # Scopes
  scope :published, -> { where(published: true) }
  scope :unpublished, -> { where(published: false) }
  scope :by_source, ->(source) { where(source: source) }

  # Callbacks
  before_save :calculate_final_price
  after_initialize :set_defaults, if: :new_record?

  ##
  # Publish product to OLX
  # Creates a new listing or updates existing one
  #
  # @return [OlxListing] The created/updated listing
  #
  def publish_to_olx
    service = OlxListingService.new(self)

    if olx_listing&.external_listing_id.present?
      # Update existing listing
      service.update_listing(olx_listing)
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
    template.gsub(/\{(\w+)\}/) do |match|
      placeholder = $1
      case placeholder.downcase
      when 'brand'
        brand.to_s
      when 'title'
        title.to_s
      when 'sku'
        sku.to_s
      when 'category'
        category.to_s
      when 'price'
        final_price.present? ? "#{final_price} #{currency}" : price.to_s
      else
        match # Keep original if not recognized
      end
    end
  end

  ##
  # Generate OLX description from product data filtered by template
  #
  # @return [String] The generated description
  #
  def generate_olx_description
    return description unless olx_category_template&.description_filter.present?
    return description unless description.present?

    allowed_fields = olx_category_template.description_filter
    filtered_lines = []

    # Parse description line by line
    description.split("\n").each do |line|
      line = line.strip
      next if line.blank?

      # Check if this line matches any allowed field (only add once)
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
    result.present? ? result : description
  end

  ##
  # Auto-populate olx_title and olx_description before publishing
  # This should be called before creating/updating OLX listings
  #
  def auto_populate_olx_fields
    self.olx_title = generate_olx_title if olx_title.blank?
    self.olx_description = generate_olx_description if olx_description.blank?
  end

  private

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
    self.final_price = base_price * (1 + margin_percentage / 100.0)
  end
end
