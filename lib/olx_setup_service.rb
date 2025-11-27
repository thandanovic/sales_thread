# frozen_string_literal: true

##
# OlxSetupService
#
# Service for setting up OLX integration by fetching and storing
# categories and locations from OLX API.
#
# Usage:
#   service = OlxSetupService.new(shop)
#   result = service.setup_all
#
class OlxSetupService
  attr_reader :shop, :logger

  def initialize(shop)
    @shop = shop
    @logger = setup_logger
  end

  ##
  # Setup all OLX data (categories and locations)
  #
  # @return [Hash] Result with counts and success status
  #
  def setup_all
    logger.info "=" * 80
    logger.info "Starting OLX Setup for Shop ##{shop.id} - #{shop.name}"
    logger.info "=" * 80

    Rails.logger.info "[OLX Setup] Starting setup for shop #{shop.id}"

    begin
      # Ensure authenticated
      logger.info "Step 1: Authenticating with OLX API..."
      OlxApiService.ensure_authenticated!(shop)
      logger.info "✓ Authentication successful"

      # Fetch categories
      logger.info ""
      logger.info "Step 2: Fetching categories from OLX..."
      categories_result = fetch_and_store_categories

      # Fetch category attributes for each category
      logger.info ""
      logger.info "Step 3: Fetching category attributes..."
      attributes_result = fetch_category_attributes

      # Fetch locations (cities)
      logger.info ""
      logger.info "Step 4: Fetching cities from OLX..."
      locations_result = fetch_and_store_locations

      logger.info ""
      logger.info "=" * 80
      logger.info "Setup completed successfully!"
      logger.info "Summary:"
      logger.info "  - Categories: #{categories_result[:created]} created, #{categories_result[:updated]} updated (total: #{categories_result[:total]})"
      logger.info "  - Attributes: #{attributes_result[:total]} total across all categories"
      logger.info "  - Cities: #{locations_result[:created]} created, #{locations_result[:updated]} updated (total: #{locations_result[:total]})"
      logger.info "=" * 80

      Rails.logger.info "[OLX Setup] Completed: #{categories_result[:total]} categories, #{attributes_result[:total]} attributes, #{locations_result[:total]} cities"

      {
        success: true,
        categories: categories_result,
        attributes: attributes_result,
        locations: locations_result
      }
    rescue => e
      logger.error ""
      logger.error "=" * 80
      logger.error "SETUP FAILED!"
      logger.error "Error: #{e.class} - #{e.message}"
      logger.error "Backtrace:"
      e.backtrace.first(10).each { |line| logger.error "  #{line}" }
      logger.error "=" * 80

      Rails.logger.error "[OLX Setup] Failed: #{e.class} - #{e.message}"
      { success: false, error: e.message }
    end
  end

  ##
  # Fetch only categories
  #
  def fetch_categories_only
    logger.info "Fetching categories from OLX..."
    OlxApiService.ensure_authenticated!(shop)
    fetch_and_store_categories
  end

  ##
  # Fetch only locations
  #
  def fetch_locations_only
    logger.info "Fetching locations from OLX..."
    OlxApiService.ensure_authenticated!(shop)
    fetch_and_store_locations
  end

  private

  ##
  # Setup dedicated logger for setup operations
  #
  def setup_logger
    log_dir = Rails.root.join('log', 'olx_sync')
    FileUtils.mkdir_p(log_dir) unless Dir.exist?(log_dir)

    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    log_file = log_dir.join("setup_shop_#{shop.id}_#{timestamp}.log")

    logger = Logger.new(log_file)
    logger.formatter = proc do |severity, datetime, progname, msg|
      "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
    end
    logger
  end

  ##
  # Fetch categories from OLX API and store in database
  #
  # @return [Hash] Result with created/updated counts
  #
  def fetch_and_store_categories
    logger.info "  Fetching from GET /categories..."

    response = OlxApiService.get('/categories', shop)

    # Debug: Log the actual response structure
    logger.info "  API Response keys: #{response.keys.join(', ')}" if response.is_a?(Hash)
    logger.info "  Full response: #{response.inspect.truncate(500)}"

    categories_data = response['data'] || response['categories'] || []

    logger.info "  ✓ Received #{categories_data.length} categories from API"

    created_count = 0
    updated_count = 0
    all_categories = []

    # First pass: collect all categories including nested ones
    categories_data.each do |category_data|
      all_categories << category_data

      # Check if category has children in the response
      if category_data['children'] && category_data['children'].any?
        logger.info "  Found #{category_data['children'].length} subcategories for #{category_data['name']}"
        collect_nested_categories(category_data['children'], all_categories)
      end
    end

    # Try to fetch subcategories for each parent category
    # Some APIs return flat list, others require recursive fetching
    categories_to_check = categories_data.map { |c| c['id'] }
    categories_to_check.each do |parent_id|
      subcategories = fetch_subcategories(parent_id)
      if subcategories.any?
        all_categories.concat(subcategories)
      end
    end

    # Remove duplicates based on external_id
    all_categories = all_categories.uniq { |c| c['id'] }

    logger.info "  ✓ Total categories to process (including subcategories): #{all_categories.length}"

    # Second pass: store all categories
    all_categories.each_with_index do |category_data, index|
      external_id = category_data['id']
      name = category_data['name']
      parent_id = category_data['parent_id']
      slug = category_data['slug']
      has_brand = category_data['show_brand'] || false
      has_shipping = category_data['shipping_available'] || false

      logger.info "  Processing category #{index + 1}/#{all_categories.length}: #{name} (ID: #{external_id}, Parent: #{parent_id || 'None'})"

      category = OlxCategory.find_or_initialize_by(external_id: external_id)

      if category.new_record?
        category.name = name
        category.parent_id = parent_id
        category.slug = slug
        category.has_brand = has_brand
        category.has_shipping = has_shipping
        category.metadata = category_data.to_json
        category.save!
        created_count += 1
        logger.info "    ✓ Created: #{name}"
      else
        # Update existing
        category.update!(
          name: name,
          parent_id: parent_id,
          slug: slug,
          has_brand: has_brand,
          has_shipping: has_shipping,
          metadata: category_data.to_json
        )
        updated_count += 1
        logger.info "    ✓ Updated: #{name}"
      end
    end

    logger.info ""
    logger.info "  Categories summary: #{created_count} created, #{updated_count} updated (total: #{all_categories.length})"

    {
      success: true,
      total: all_categories.length,
      created: created_count,
      updated: updated_count
    }
  rescue => e
    logger.error "  ✗ Failed to fetch categories: #{e.message}"
    Rails.logger.error "[OLX Setup] Categories error: #{e.message}"
    { success: false, error: e.message, total: 0, created: 0, updated: 0 }
  end

  ##
  # Recursively collect nested categories from children arrays
  #
  def collect_nested_categories(children, all_categories)
    children.each do |child|
      all_categories << child
      if child['children'] && child['children'].any?
        collect_nested_categories(child['children'], all_categories)
      end
    end
  end

  ##
  # Try to fetch subcategories for a given parent category
  # Returns empty array if endpoint doesn't exist or no subcategories found
  #
  def fetch_subcategories(parent_id)
    begin
      # Try /categories/:id endpoint which might return category with children
      response = OlxApiService.get("/categories/#{parent_id}", shop)
      category_data = response['data'] || response['category'] || {}

      if category_data['children'] && category_data['children'].any?
        logger.info "  Fetched #{category_data['children'].length} subcategories for category #{parent_id}"
        subcats = []
        collect_nested_categories(category_data['children'], subcats)
        return subcats
      end
    rescue => e
      # Silently ignore - not all APIs support this endpoint
      logger.debug "  No subcategories endpoint for #{parent_id}: #{e.message}"
    end
    []
  end

  ##
  # Fetch attributes for all categories
  #
  # @return [Hash] Result with total attribute count
  #
  def fetch_category_attributes
    categories = OlxCategory.all
    total_attributes = 0

    logger.info "  Processing attributes for #{categories.count} categories..."

    categories.each do |category|
      begin
        logger.info "  Fetching attributes for: #{category.name} (ID: #{category.external_id})"

        response = OlxApiService.get("/categories/#{category.external_id}/attributes", shop)
        attributes_data = response['data'] || response['attributes'] || []

        if attributes_data.any?
          logger.info "    Found #{attributes_data.length} attributes"

          attributes_data.each do |attr_data|
            attr_external_id = attr_data['id']
            attr_name = attr_data['name']
            attr_type = attr_data['type']  # e.g., "select", "number", "text"
            input_type = attr_data['input_type']  # e.g., "text", "select", "number"
            required = attr_data['required'] || false
            options = attr_data['options'] || []

            # Find or create attribute
            attribute = OlxCategoryAttribute.find_or_initialize_by(
              olx_category: category,
              external_id: attr_external_id
            )

            attribute.name = attr_name
            attribute.attribute_type = attr_type
            attribute.input_type = input_type
            attribute.required = required
            attribute.options = options.to_json
            attribute.save!

            total_attributes += 1
          end

          logger.info "    ✓ Stored #{attributes_data.length} attributes"
        else
          logger.info "    No attributes for this category"
        end
      rescue => e
        logger.warn "    ! Failed to fetch attributes for #{category.name}: #{e.message}"
      end
    end

    logger.info ""
    logger.info "  Attributes summary: #{total_attributes} total attributes across #{categories.count} categories"

    { success: true, total: total_attributes }
  rescue => e
    logger.error "  ✗ Failed to fetch category attributes: #{e.message}"
    { success: false, total: 0 }
  end

  ##
  # Fetch locations from OLX API and store in database
  #
  # @return [Hash] Result with created/updated counts
  #
  def fetch_and_store_locations
    logger.info "  Trying GET /cities..."

    # Try /cities first (common OLX endpoint)
    response = OlxApiService.get('/cities', shop)

    # Debug: Log the actual response structure
    logger.info "  API Response keys: #{response.keys.join(', ')}" if response.is_a?(Hash)
    logger.info "  Full response: #{response.inspect.truncate(500)}"

    locations_data = response['data'] || response['cities'] || response['locations'] || []

    if locations_data.empty?
      logger.warn "  ! No locations returned from /cities endpoint"
      logger.info "  Note: OLX.ba appears to use GPS coordinates instead of city IDs"
      logger.info "  Locations are optional - products can sync with categories only"
      return { success: true, total: 0, created: 0, updated: 0 }
    end

    logger.info "  ✓ Received #{locations_data.length} locations from API"

    created_count = 0
    updated_count = 0

    locations_data.each_with_index do |location_data, index|
      external_id = location_data['id']
      name = location_data['name']
      region_id = location_data['region_id']

      logger.info "  Processing location #{index + 1}/#{locations_data.length}: #{name} (ID: #{external_id})"

      location = OlxLocation.find_or_initialize_by(external_id: external_id)

      if location.new_record?
        location.name = name
        location.region_external_id = region_id
        location.metadata = location_data.to_json
        location.save!
        created_count += 1
        logger.info "    ✓ Created: #{name}"
      else
        # Update existing
        location.update!(
          name: name,
          region_external_id: region_id,
          metadata: location_data.to_json
        )
        updated_count += 1
        logger.info "    ✓ Updated: #{name}"
      end
    end

    logger.info ""
    logger.info "  Locations summary: #{created_count} created, #{updated_count} updated (total: #{locations_data.length})"

    {
      success: true,
      total: locations_data.length,
      created: created_count,
      updated: updated_count
    }
  rescue => e
    # Locations are optional - don't fail the entire setup
    logger.warn "  ! Could not fetch locations: #{e.message}"
    logger.info "  Note: OLX.ba appears to use GPS coordinates instead of city IDs"
    logger.info "  Locations are optional - products can sync with categories only"
    Rails.logger.info "[OLX Setup] Locations not available (using GPS coordinates): #{e.message}"
    { success: true, total: 0, created: 0, updated: 0 }
  end
end
