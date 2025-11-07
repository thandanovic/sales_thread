# frozen_string_literal: true

##
# OlxListingService
#
# Service for creating and managing product listings on OLX.
# Handles mapping product data to OLX listing format and pushing to OLX API.
#
# Usage:
#   # Create a new listing
#   service = OlxListingService.new(product)
#   result = service.create_listing
#
#   # Publish a listing
#   service.publish_listing(olx_listing)
#
#   # Update existing listing
#   service.update_listing(olx_listing)
#
class OlxListingService
  attr_reader :product, :shop

  ##
  # Initialize service with a product
  #
  # @param product [Product] Product to create listing for
  #
  def initialize(product)
    @product = product
    @shop = product.shop
    @template = product.olx_category_template
  end

  ##
  # Create a new OLX listing for the product
  #
  # @return [OlxListing] Created listing
  # @raise [StandardError] If listing creation fails
  #
  def create_listing
    Rails.logger.info "[OLX Listing] Starting listing creation for product #{product.id} (#{product.title})"

    validate_product!
    Rails.logger.info "[OLX Listing] Validation passed"

    # Create or update local OlxListing record
    olx_listing = product.olx_listing || product.build_olx_listing(shop: shop)
    olx_listing.status = 'pending'
    olx_listing.save!
    Rails.logger.info "[OLX Listing] Local listing record created/updated (id: #{olx_listing.id})"

    begin
      # Build listing payload
      payload = build_listing_payload
      Rails.logger.info "[OLX Listing] Payload built: #{payload.inspect}"

      # Create listing on OLX
      Rails.logger.info "[OLX Listing] Sending POST request to OLX API /listings"
      response = OlxApiService.post('/listings', payload, shop)
      Rails.logger.info "[OLX Listing] OLX API response: #{response.inspect}"

      # Update local record with OLX data
      olx_listing.update!(
        external_listing_id: response['id'],
        status: response['status']&.downcase || 'draft',
        metadata: response
      )

      Rails.logger.info "[OLX Listing] ✓ Successfully created listing #{response['id']} for product #{product.id}"

      # Upload images if product has image URLs
      if product.image_urls.present? && product.image_urls.any?
        Rails.logger.info "[OLX Listing] Uploading #{product.image_urls.length} images..."
        uploaded_images = OlxApiService.upload_images(response['id'], product.image_urls, shop)
        Rails.logger.info "[OLX Listing] ✓ Uploaded #{uploaded_images.length} images"
      else
        Rails.logger.info "[OLX Listing] No images to upload"
      end

      olx_listing
    rescue StandardError => e
      error_details = {
        error: e.message,
        error_class: e.class.name,
        timestamp: Time.current,
        backtrace: e.backtrace&.first(5)
      }

      olx_listing.update!(
        status: 'failed',
        metadata: error_details
      )

      Rails.logger.error "[OLX Listing] ✗ Failed to create listing for product #{product.id}"
      Rails.logger.error "[OLX Listing] Error: #{e.class.name} - #{e.message}"
      Rails.logger.error "[OLX Listing] Backtrace: #{e.backtrace&.first(3)&.join("\n")}"
      raise
    end
  end

  ##
  # Update existing OLX listing
  #
  # @param olx_listing [OlxListing] Listing to update
  # @return [OlxListing] Updated listing
  #
  def update_listing(olx_listing)
    raise ArgumentError, 'Listing must have external_listing_id' unless olx_listing.external_listing_id.present?

    begin
      Rails.logger.info "[OLX Listing] Updating listing #{olx_listing.external_listing_id} for product #{product.id}"

      payload = build_listing_payload
      Rails.logger.info "[OLX Listing] Update payload: #{payload.inspect}"

      response = OlxApiService.put("/listings/#{olx_listing.external_listing_id}", payload, shop)

      olx_listing.update!(
        status: response['status']&.downcase || olx_listing.status,
        metadata: response
      )

      Rails.logger.info "[OLX Listing] ✓ Successfully updated listing #{olx_listing.external_listing_id}"

      # Upload images if product has image URLs
      if product.image_urls.present? && product.image_urls.any?
        Rails.logger.info "[OLX Listing] Uploading #{product.image_urls.length} images to existing listing..."
        uploaded_images = OlxApiService.upload_images(olx_listing.external_listing_id, product.image_urls, shop)
        Rails.logger.info "[OLX Listing] ✓ Uploaded #{uploaded_images.length} images"
      else
        Rails.logger.info "[OLX Listing] No images to upload"
      end

      olx_listing
    rescue StandardError => e
      Rails.logger.error "[OLX Listing] ✗ Failed to update listing #{olx_listing.external_listing_id}: #{e.message}"
      Rails.logger.error "[OLX Listing] Backtrace: #{e.backtrace&.first(3)&.join("\n")}"
      raise
    end
  end

  ##
  # Publish a draft listing on OLX
  #
  # @param olx_listing [OlxListing] Listing to publish
  # @return [OlxListing] Published listing
  #
  def publish_listing(olx_listing)
    raise ArgumentError, 'Listing must have external_listing_id' unless olx_listing.external_listing_id.present?

    begin
      response = OlxApiService.post("/listings/#{olx_listing.external_listing_id}/publish", {}, shop)

      olx_listing.update!(
        status: 'published',
        published_at: Time.current,
        metadata: olx_listing.metadata.merge(response)
      )

      Rails.logger.info "[OLX Listing] Published listing #{olx_listing.external_listing_id}"
      olx_listing
    rescue StandardError => e
      Rails.logger.error "[OLX Listing] Failed to publish listing #{olx_listing.external_listing_id}: #{e.message}"
      raise
    end
  end

  ##
  # Unpublish (deactivate) a listing on OLX
  #
  # @param olx_listing [OlxListing] Listing to unpublish
  # @return [OlxListing] Unpublished listing
  #
  def unpublish_listing(olx_listing)
    raise ArgumentError, 'Listing must have external_listing_id' unless olx_listing.external_listing_id.present?

    begin
      response = OlxApiService.post("/listings/#{olx_listing.external_listing_id}/unpublish", {}, shop)

      olx_listing.update!(
        status: 'draft',
        metadata: olx_listing.metadata.merge(response)
      )

      Rails.logger.info "[OLX Listing] Unpublished listing #{olx_listing.external_listing_id}"
      olx_listing
    rescue StandardError => e
      Rails.logger.error "[OLX Listing] Failed to unpublish listing #{olx_listing.external_listing_id}: #{e.message}"
      raise
    end
  end

  ##
  # Delete a listing from OLX
  #
  # @param olx_listing [OlxListing] Listing to delete
  # @return [Boolean] true if successful
  #
  def delete_listing(olx_listing)
    raise ArgumentError, 'Listing must have external_listing_id' unless olx_listing.external_listing_id.present?

    begin
      OlxApiService.delete("/listings/#{olx_listing.external_listing_id}", shop)

      olx_listing.update!(
        status: 'removed',
        metadata: olx_listing.metadata.merge(removed_at: Time.current)
      )

      Rails.logger.info "[OLX Listing] Deleted listing #{olx_listing.external_listing_id}"
      true
    rescue StandardError => e
      Rails.logger.error "[OLX Listing] Failed to delete listing #{olx_listing.external_listing_id}: #{e.message}"
      raise
    end
  end

  private

  ##
  # Validate product has required data for OLX listing
  #
  def validate_product!
    errors = []

    if product.title.blank?
      errors << 'Product must have title'
      Rails.logger.error "[OLX Listing] Validation failed: Product missing title"
    end

    if @template.nil?
      errors << 'Product must be associated with a category template'
      Rails.logger.error "[OLX Listing] Validation failed: No category template assigned to product #{product.id}"
    end

    if @template && @template.olx_location.nil?
      errors << 'Category template must have location'
      Rails.logger.error "[OLX Listing] Validation failed: Template #{@template.id} missing location"
    end

    if @template && @template.olx_category.nil?
      errors << 'Category template must have category'
      Rails.logger.error "[OLX Listing] Validation failed: Template #{@template.id} missing category"
    end

    if errors.any?
      raise ArgumentError, errors.join(', ')
    end
  end

  ##
  # Build OLX API listing payload from product and template
  #
  # @return [Hash] Listing data for OLX API
  #
  def build_listing_payload
    # Auto-populate olx_title and olx_description if blank
    product.auto_populate_olx_fields
    product.save if product.changed?

    payload = {
      title: product.olx_title.presence || product.title,
      description: product.olx_description.presence || build_description,
      price: product.final_price || product.price,
      category_id: @template.olx_category.external_id,
      city_id: @template.olx_location.external_id,
      listing_type: @template.default_listing_type || 'sell',
      state: @template.default_state || 'new'
    }

    Rails.logger.info "[OLX Listing] Building payload with category_id: #{@template.olx_category.external_id}, city_id: #{@template.olx_location.external_id}"
    Rails.logger.info "[OLX Listing] Using title: #{payload[:title].truncate(50)}"

    # Add optional fields
    short_desc = product.olx_description.presence || product.description
    payload[:short_description] = truncate_text(short_desc, 100) if short_desc.present?
    payload[:sku_number] = product.sku if product.sku.present?
    payload[:available] = product.stock.to_i > 0 if product.respond_to?(:stock)

    # Add category-specific attributes
    # Always include attributes field (OLX may require it even if empty for some categories)
    attributes = build_category_attributes
    payload[:attributes] = attributes

    payload
  end

  ##
  # Build description from product data, filtered by template settings
  #
  # @return [String]
  #
  def build_description
    # If template has description_filter configured, use it to filter
    if @template.description_filter.present? && @template.description_filter.any?
      return filter_description_by_template
    end

    # Default: include full description
    parts = []
    parts << product.description if product.description.present?
    parts << "\nSKU: #{product.sku}" if product.sku.present?
    parts << "\nBrand: #{product.brand}" if product.respond_to?(:brand) && product.brand.present?
    parts << "\nStock: #{product.stock}" if product.respond_to?(:stock) && product.stock.to_i > 0

    description = parts.join("\n").strip
    description.present? ? description : product.title
  end

  ##
  # Filter product description based on template's description_filter
  #
  # @return [String]
  #
  def filter_description_by_template
    return product.title unless product.description.present?

    allowed_fields = @template.description_filter
    filtered_lines = []

    # Parse description line by line
    product.description.split("\n").each do |line|
      line = line.strip
      next if line.blank?

      # Check if this line matches any allowed field (only add once)
      line_matched = false
      allowed_fields.each do |field|
        break if line_matched  # Skip if line already matched

        # Convert field identifier to regex patterns
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
    if allowed_fields.include?('sku') && product.sku.present?
      sku_line = "SKU: #{product.sku}"
      filtered_lines << sku_line unless filtered_lines.any? { |l| l.include?("SKU:") }
    end

    if allowed_fields.include?('brand') && product.respond_to?(:brand) && product.brand.present?
      brand_line = "Brand: #{product.brand}"
      filtered_lines << brand_line unless filtered_lines.any? { |l| l.match?(/Brand:|Brend:/i) }
    end

    description = filtered_lines.join("\n")
    description.present? ? description : product.title
  end

  ##
  # Convert field identifier to regex patterns
  #
  # @param field [String] Field identifier
  # @return [Array<String>] Array of patterns to match
  #
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

  ##
  # Build category-specific attributes from template mappings
  #
  # @return [Array<Hash>] Array of attribute hashes with id and value
  #
  def build_category_attributes
    attributes = []
    category_attributes = @template.olx_category.olx_category_attributes

    # Auto-extract tyre attributes if category is "Gume za automobile" (940)
    if @template.olx_category.external_id == 940
      attributes = build_tyre_attributes(category_attributes)
    end

    # Add template mappings (will override auto-extracted values)
    if @template.attribute_mappings.present?
      @template.attribute_mappings.each do |attr_name, mapping|
        # Find the attribute definition
        attr_def = category_attributes.find { |a| a.name == attr_name || a.external_id.to_s == attr_name.to_s }
        next unless attr_def

        # Resolve the value from mapping
        value = resolve_attribute_value(mapping)
        next if value.blank?

        # Clean numeric values for number-type attributes
        if attr_def.attribute_type == 'number' && value.is_a?(String)
          # Extract just the numeric value (e.g., "77.0 Ah" -> "77")
          numeric_match = value.match(/(\d+(?:\.\d+)?)/)
          value = numeric_match[1].to_f.to_i.to_s if numeric_match
        end

        # Replace existing attribute or add new one
        existing_index = attributes.find_index { |a| a[:id] == attr_def.external_id }
        if existing_index
          attributes[existing_index][:value] = value
        else
          attributes << {
            id: attr_def.external_id,
            value: value
          }
        end
      end
    end

    attributes
  end

  ##
  # Resolve attribute value from mapping rule
  #
  # @param mapping [String] Mapping rule (e.g., "product.brand", "fixed:New", "template.default_state", "extract:width")
  # @return [String, nil] Resolved value
  #
  def resolve_attribute_value(mapping)
    return nil if mapping.blank?

    # Handle fixed values
    if mapping.start_with?('fixed:')
      return mapping.sub('fixed:', '')
    end

    # Handle product field references
    if mapping.start_with?('product.')
      field = mapping.sub('product.', '')
      return product.send(field) if product.respond_to?(field)
    end

    # Handle template field references
    if mapping.start_with?('template.')
      field = mapping.sub('template.', '')
      return @template.send(field) if @template.respond_to?(field)
    end

    # Handle extract from description/specs
    if mapping.start_with?('extract:')
      keyword = mapping.sub('extract:', '')
      return extract_from_description(keyword)
    end

    nil
  rescue StandardError => e
    Rails.logger.warn "[OLX Listing] Failed to resolve attribute mapping '#{mapping}': #{e.message}"
    nil
  end

  ##
  # Extract value from product description or specs using keyword
  #
  # @param keyword [String] Keyword to search for
  # @return [String, nil] Extracted value
  #
  def extract_from_description(keyword)
    # Search in description
    if product.description.present?
      # Try to find pattern like "keyword: value" or "keyword value"
      match = product.description.match(/#{Regexp.escape(keyword)}\s*:?\s*([^\n,;]+)/i)
      return match[1].strip if match
    end

    # Search in specs JSON
    if product.respond_to?(:specs) && product.specs.present?
      specs = JSON.parse(product.specs) rescue {}

      # Try exact key match (case insensitive)
      specs.each do |key, value|
        return value.to_s if key.to_s.downcase == keyword.downcase
      end

      # Try partial key match
      specs.each do |key, value|
        return value.to_s if key.to_s.downcase.include?(keyword.downcase)
      end
    end

    nil
  rescue StandardError => e
    Rails.logger.warn "[OLX Listing] Failed to extract '#{keyword}' from description: #{e.message}"
    nil
  end

  ##
  # Truncate text to specified length
  #
  # @param text [String] Text to truncate
  # @param length [Integer] Maximum length
  # @return [String]
  #
  def truncate_text(text, length)
    return '' if text.blank?

    text.length > length ? "#{text[0...length]}..." : text
  end

  ##
  # Build tyre-specific attributes by parsing product title and description
  #
  # @param category_attributes [Array<OlxCategoryAttribute>] Category attributes
  # @return [Array<Hash>] Array of attribute hashes
  #
  def build_tyre_attributes(category_attributes)
    attributes = []

    # Parse tyre size from title (e.g., "225/55R19" or "225/55/19")
    if product.title =~ /(\d{3})[\/-](\d{2})[\/-]?R?(\d{2})/i
      width = $1
      height = $2
      diameter = $3

      # Širina (Width) - ID 2918
      width_attr = category_attributes.find { |a| a.external_id == 2918 }
      attributes << { id: 2918, value: width } if width_attr

      # Visina (Height) - ID 2919
      height_attr = category_attributes.find { |a| a.external_id == 2919 }
      attributes << { id: 2919, value: height } if height_attr

      # Veličina (Diameter) - ID 1849
      diameter_attr = category_attributes.find { |a| a.external_id == 1849 }
      attributes << { id: 1849, value: diameter } if diameter_attr
    end

    # Extract tyre type from description
    type_value = nil
    if product.description.present?
      desc = product.description.downcase
      if desc.include?('sezona: zima') || desc.include?('zimsk')
        type_value = 'Zimske'
      elsif desc.include?('sezona: ljeto') || desc.include?('ljetn')
        type_value = 'Ljetne'
      elsif desc.include?('all season') || desc.include?('cjelogodišnj')
        type_value = 'All season (Cjelogodišnje)'
      end
    end

    # Vrsta (Type) - ID 1848
    if type_value
      type_attr = category_attributes.find { |a| a.external_id == 1848 }
      attributes << { id: 1848, value: type_value } if type_attr
    end

    attributes
  end
end
