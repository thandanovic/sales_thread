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
  # Reconnect to a previously disconnected OLX listing
  # Creates a new local OlxListing record linked to the existing OLX listing
  #
  # @param external_id [String] The external listing ID to reconnect to
  # @return [OlxListing] The reconnected listing
  #
  def reconnect_listing(external_id)
    Rails.logger.info "[OLX Listing] Reconnecting product #{product.id} to existing OLX listing #{external_id}"

    begin
      # Fetch the current listing data from OLX to verify it exists and get its status
      response = OlxApiService.get("/listings/#{external_id}", shop)
      Rails.logger.info "[OLX Listing] Found existing listing on OLX: #{response['id']} (status: #{response['status']})"

      # Create local OlxListing record linked to the existing OLX listing
      olx_listing = product.olx_listing || product.build_olx_listing(shop: shop)
      olx_listing.update!(
        external_listing_id: external_id,
        status: response['status']&.downcase || 'active',
        metadata: response
      )

      # Clear the olx_external_id from product since we're now connected
      product.update_column(:olx_external_id, nil)

      Rails.logger.info "[OLX Listing] ✓ Successfully reconnected product #{product.id} to listing #{external_id}"
      olx_listing
    rescue StandardError => e
      Rails.logger.error "[OLX Listing] ✗ Failed to reconnect to listing #{external_id}: #{e.message}"
      Rails.logger.error "[OLX Listing] Backtrace: #{e.backtrace&.first(3)&.join("\n")}"

      # If reconnection fails (listing may have been deleted on OLX), clear the stored ID
      # and let the user create a new listing
      product.update_column(:olx_external_id, nil)
      raise StandardError, "Could not reconnect to OLX listing #{external_id}. The listing may have been deleted on OLX. Please try publishing again to create a new listing."
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

    if @template && @template.olx_category.nil?
      errors << 'Category template must have category'
      Rails.logger.error "[OLX Listing] Validation failed: Template #{@template.id} missing category"
    end

    # Note: olx_location is optional for OLX.ba since it uses GPS coordinates

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

    # OLX has a 65 character limit for titles
    raw_title = product.olx_title.presence || product.title
    truncated_title = raw_title.to_s.truncate(65, omission: '')

    payload = {
      title: truncated_title,
      description: product.olx_description.presence || build_description,
      price: (product.final_price || product.price).to_f.round(0),
      category_id: @template.olx_category.external_id,
      listing_type: @template.default_listing_type || 'sell',
      state: @template.default_state || 'new'
    }

    # Add location: Use city_id if available, otherwise use GPS coordinates
    if @template.olx_location.present?
      payload[:city_id] = @template.olx_location.external_id
      Rails.logger.info "[OLX Listing] Building payload with category_id: #{@template.olx_category.external_id}, city_id: #{@template.olx_location.external_id}"
    else
      # OLX.ba uses GPS coordinates instead of city IDs
      # Try to get coordinates from synced listing metadata or use default Sarajevo coordinates
      location_data = nil

      if product.olx_listing&.metadata.present?
        # Check for location in synced listing metadata
        location_data = product.olx_listing.metadata['location']
      end

      if location_data && location_data['lat'] && location_data['lon']
        payload[:location] = {
          lat: location_data['lat'],
          lon: location_data['lon']
        }
        Rails.logger.info "[OLX Listing] Building payload with category_id: #{@template.olx_category.external_id}, GPS: #{location_data['lat']},#{location_data['lon']}"
      else
        # Default coordinates for Sarajevo, Bosnia
        payload[:location] = {
          lat: 43.8563,
          lon: 18.4131
        }
        Rails.logger.info "[OLX Listing] Building payload with category_id: #{@template.olx_category.external_id}, GPS: default Sarajevo"
      end
    end

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

    # For products synced from OLX, use ONLY the original attributes from metadata
    # Do NOT generate or apply template mappings - just push back what was synced
    if product.source == 'olx' && product.olx_listing&.metadata.present?
      # Attributes are stored in metadata['data']['attributes'] from the API response
      original_attrs = product.olx_listing.metadata.dig('data', 'attributes') ||
                       product.olx_listing.metadata['attributes'] || []

      original_attrs.each do |attr|
        attr_id = attr['id']
        attr_value = attr['value']

        if attr_id.present? && attr_value.present?
          attributes << {
            id: attr_id,
            value: attr_value
          }
        end
      end

      Rails.logger.info "[OLX Listing] Using #{attributes.length} original attributes from synced product (no generation/mapping)"
      return attributes  # Return immediately - don't process templates
    end

    # For non-OLX products: Auto-extract tyre attributes if category is "Gume za automobile" (940)
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

        # Try to match value against attribute options if available
        if attr_def.options.present?
          value = match_attribute_option(value, attr_def.options)
        end
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
  # @param mapping [String] Mapping rule (e.g., "product.brand", "fixed:New", "template.default_state", "extract:width", "{boja}")
  # @return [String, nil] Resolved value
  #
  def resolve_attribute_value(mapping)
    return nil if mapping.blank?

    # Handle fallback syntax: {placeholder} | fallback_value
    # e.g., "{Boja} | Neutralna" means use Boja from specs, or "Neutralna" if not found
    if mapping.include?('|')
      parts = mapping.split('|').map(&:strip)
      parts.each do |part|
        value = resolve_single_value(part)
        return value if value.present?
      end
      return nil
    end

    resolve_single_value(mapping)
  end

  ##
  # Resolve a single value (without fallback chain)
  #
  def resolve_single_value(mapping)
    return nil if mapping.blank?

    # Handle placeholder syntax like {boja}, {strana_ugradnje}
    # This extracts value from product specs using the placeholder name
    if mapping =~ /^\{([^\}]+)\}$/
      placeholder = $1
      return resolve_spec_placeholder(placeholder)
    end

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

    # If nothing else matched, treat as a plain text value (for fallbacks like "Neutralna")
    mapping
  rescue StandardError => e
    Rails.logger.warn "[OLX Listing] Failed to resolve attribute mapping '#{mapping}': #{e.message}"
    nil
  end

  ##
  # Resolve a placeholder to a value from product fields or specs
  # Supports snake_case placeholders matching spec keys with spaces/special chars
  # e.g., {boja} matches "Boja", {strana_ugradnje} matches "Strana ugradnje"
  # Also supports direct product fields like {models}, {technical_description}, {sub_title}
  #
  # @param placeholder [String] The placeholder name without braces
  # @return [String, nil] The resolved value or nil
  #
  def resolve_spec_placeholder(placeholder)
    # First try direct product field mapping
    product_field_value = resolve_product_field(placeholder)
    if product_field_value.present?
      Rails.logger.info "[OLX Listing] Resolved placeholder {#{placeholder}} -> '#{product_field_value}' (product field)"
      return product_field_value
    end

    # Then try specs lookup
    return nil unless product.specs.present?

    specs_hash = JSON.parse(product.specs) rescue {}
    return nil if specs_hash.empty?

    # Normalize placeholder for comparison
    normalized_placeholder = normalize_key(placeholder)

    # Try to find matching spec key
    specs_hash.each do |key, value|
      normalized_key = normalize_key(key)
      if normalized_key == normalized_placeholder
        Rails.logger.info "[OLX Listing] Resolved placeholder {#{placeholder}} -> '#{value}' (matched key: #{key})"
        return value
      end
    end

    Rails.logger.warn "[OLX Listing] Could not resolve placeholder {#{placeholder}} - no matching spec found in: #{specs_hash.keys.join(', ')}"
    nil
  end

  ##
  # Resolve a placeholder to a direct product field value
  #
  # @param placeholder [String] The placeholder name
  # @return [String, nil] The field value or nil
  #
  def resolve_product_field(placeholder)
    case placeholder.downcase
    when 'title', 'naslov'
      product.title
    when 'sub_title', 'subtitle', 'podnaslov'
      product.sub_title
    when 'brand', 'brend'
      product.brand
    when 'sku', 'sifra'
      product.sku
    when 'category', 'kategorija'
      product.category
    when 'technical_description', 'tehnicki_opis'
      product.technical_description
    when 'models', 'modeli', 'odgovara'
      product.models
    when 'description', 'opis'
      product.description
    else
      nil
    end
  end

  ##
  # Normalize a key for comparison (lowercase, replace underscores with spaces, remove accents)
  #
  # @param key [String] The key to normalize
  # @return [String] Normalized key
  #
  def normalize_key(key)
    key.to_s
       .downcase
       .gsub('_', ' ')
       .gsub('č', 'c').gsub('ć', 'c')
       .gsub('š', 's').gsub('ž', 'z')
       .gsub('đ', 'd')
       .strip
  end

  ##
  # Match a value against OLX attribute options using fuzzy matching
  # Handles cases like "Desno" matching "Desni", "Lijevo" matching "Lijevi"
  #
  # @param value [String] The value to match
  # @param options [String, Array] The available options (JSON string or array)
  # @return [String, nil] The matched option or nil
  #
  def match_attribute_option(value, options)
    return value if value.blank?

    # Parse options if it's a JSON string
    opts = options.is_a?(String) ? (JSON.parse(options) rescue []) : options
    return value if opts.empty?

    value_str = value.to_s.strip
    normalized_value = normalize_key(value_str)

    # Try exact match first
    exact_match = opts.find { |o| o.to_s.strip == value_str }
    return exact_match if exact_match

    # Try case-insensitive match
    case_match = opts.find { |o| o.to_s.strip.downcase == value_str.downcase }
    return case_match if case_match

    # Try normalized match (handles accents)
    normalized_match = opts.find { |o| normalize_key(o) == normalized_value }
    return normalized_match if normalized_match

    # Try prefix/stem matching for Bosnian/Croatian word endings
    # e.g., "Desno" -> "Desni", "Lijevo" -> "Lijevi", "Crno" -> "Crna"
    stem_match = opts.find do |o|
      opt_normalized = normalize_key(o)
      # Check if they share at least 3 chars in common and differ only in ending
      if normalized_value.length >= 3 && opt_normalized.length >= 3
        # Use first 3 chars as stem to handle gender variations (crno/crna, bijelo/bijela)
        stem_length = [normalized_value.length - 1, opt_normalized.length - 1, 3].min
        common_stem = normalized_value[0...stem_length]
        opt_stem = opt_normalized[0...stem_length]
        common_stem == opt_stem
      end
    end
    return stem_match if stem_match

    # Try contains match as last resort
    contains_match = opts.find { |o| normalize_key(o).include?(normalized_value) || normalized_value.include?(normalize_key(o)) }
    return contains_match if contains_match

    Rails.logger.warn "[OLX Listing] Could not match value '#{value}' to options: #{opts.join(', ')}"
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
