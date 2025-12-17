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
  # First imports from CSV seed files, then supplements from API if needed
  #
  # @return [Hash] Result with counts and success status
  #
  def setup_all
    logger.info "=" * 80
    logger.info "Starting OLX Setup for Shop ##{shop.id} - #{shop.name}"
    logger.info "=" * 80

    Rails.logger.info "[OLX Setup] Starting setup for shop #{shop.id}"

    begin
      # Step 1: Import categories and attributes from CSV seed files (comprehensive data)
      logger.info "Step 1: Importing categories from CSV seed files..."
      csv_categories_result = import_categories_from_csv

      logger.info ""
      logger.info "Step 2: Importing category attributes from CSV seed files..."
      csv_attributes_result = import_attributes_from_csv

      # Step 2: Authenticate and try to fetch additional data from API
      logger.info ""
      logger.info "Step 3: Authenticating with OLX API..."
      OlxApiService.ensure_authenticated!(shop)
      logger.info "✓ Authentication successful"

      # Fetch any additional categories from API (in case there are new ones)
      logger.info ""
      logger.info "Step 4: Checking for new categories from OLX API..."
      api_categories_result = fetch_and_store_categories

      # Fetch locations (cities)
      logger.info ""
      logger.info "Step 5: Fetching cities from OLX..."
      locations_result = fetch_and_store_locations

      # Import templates from CSV
      logger.info ""
      logger.info "Step 6: Importing category templates from CSV..."
      templates_result = import_templates_from_csv

      # Calculate totals
      total_categories = OlxCategory.count
      total_attributes = OlxCategoryAttribute.count
      total_templates = shop.olx_category_templates.count

      logger.info ""
      logger.info "=" * 80
      logger.info "Setup completed successfully!"
      logger.info "Summary:"
      logger.info "  - Categories from CSV: #{csv_categories_result[:created]} created, #{csv_categories_result[:updated]} updated"
      logger.info "  - Categories from API: #{api_categories_result[:created]} new, #{api_categories_result[:updated]} updated"
      logger.info "  - Total categories: #{total_categories}"
      logger.info "  - Attributes from CSV: #{csv_attributes_result[:created]} created, #{csv_attributes_result[:updated]} updated"
      logger.info "  - Total attributes: #{total_attributes}"
      logger.info "  - Cities: #{locations_result[:created]} created, #{locations_result[:updated]} updated (total: #{locations_result[:total]})"
      logger.info "  - Templates: #{templates_result[:created]} created, #{templates_result[:updated]} updated (total: #{total_templates})"
      logger.info "=" * 80

      Rails.logger.info "[OLX Setup] Completed: #{total_categories} categories, #{total_attributes} attributes, #{locations_result[:total]} cities, #{total_templates} templates"

      {
        success: true,
        categories: { total: total_categories, csv: csv_categories_result, api: api_categories_result },
        attributes: { total: total_attributes, csv: csv_attributes_result },
        locations: locations_result,
        templates: { total: total_templates, created: templates_result[:created], updated: templates_result[:updated] }
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

  ##
  # Import only from CSV files (without API calls)
  # Useful for quick setup or when API is not available
  #
  def import_from_csv_only
    logger.info "=" * 80
    logger.info "Importing OLX data from CSV files only"
    logger.info "=" * 80

    categories_result = import_categories_from_csv
    attributes_result = import_attributes_from_csv
    templates_result = import_templates_from_csv

    total_categories = OlxCategory.count
    total_attributes = OlxCategoryAttribute.count
    total_templates = shop.olx_category_templates.count

    logger.info ""
    logger.info "=" * 80
    logger.info "CSV Import completed!"
    logger.info "Summary:"
    logger.info "  - Categories: #{categories_result[:created]} created, #{categories_result[:updated]} updated (total: #{total_categories})"
    logger.info "  - Attributes: #{attributes_result[:created]} created, #{attributes_result[:updated]} updated (total: #{total_attributes})"
    logger.info "  - Templates: #{templates_result[:created]} created, #{templates_result[:updated]} updated (total: #{total_templates})"
    logger.info "=" * 80

    {
      success: true,
      categories: { total: total_categories, created: categories_result[:created], updated: categories_result[:updated] },
      attributes: { total: total_attributes, created: attributes_result[:created], updated: attributes_result[:updated] },
      templates: { total: total_templates, created: templates_result[:created], updated: templates_result[:updated] }
    }
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
  # Uses two-pass approach: first create all categories, then update parent relationships
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

    logger.info "  ✓ Received #{categories_data.length} root categories from API"

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

    # First pass: store all categories WITHOUT parent relationships
    all_categories.each_with_index do |category_data, index|
      external_id = category_data['id']
      name = category_data['name']
      slug = category_data['slug']
      has_brand = category_data['show_brand'] || false
      has_shipping = category_data['shipping_available'] || false

      logger.info "  Processing category #{index + 1}/#{all_categories.length}: #{name} (ID: #{external_id})"

      category = OlxCategory.find_or_initialize_by(external_id: external_id)

      if category.new_record?
        category.name = name
        category.slug = slug
        category.has_brand = has_brand
        category.has_shipping = has_shipping
        category.metadata = category_data.to_json
        category.save!
        created_count += 1
        logger.info "    ✓ Created: #{name}"
      else
        # Update existing (but don't touch parent_id yet)
        category.update!(
          name: name,
          slug: slug,
          has_brand: has_brand,
          has_shipping: has_shipping,
          metadata: category_data.to_json
        )
        updated_count += 1
        logger.info "    ✓ Updated: #{name}"
      end
    end

    # Second pass: update parent relationships
    # Build lookup of external_id -> database_id
    external_to_db_id = OlxCategory.pluck(:external_id, :id).to_h

    logger.info "  Updating parent relationships..."
    all_categories.each do |category_data|
      next unless category_data['parent_id'].present?

      external_id = category_data['id']
      parent_external_id = category_data['parent_id']

      category = OlxCategory.find_by(external_id: external_id)
      next unless category

      parent_db_id = external_to_db_id[parent_external_id]
      if parent_db_id && category.parent_id != parent_db_id
        category.update_column(:parent_id, parent_db_id)
        logger.debug "    ✓ Set parent for #{category.name}: external #{parent_external_id} -> DB ID #{parent_db_id}"
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

  ##
  # Import categories from CSV seed file
  # Uses two-pass approach: first create all categories, then update parent relationships
  #
  # @return [Hash] Result with created/updated counts
  #
  def import_categories_from_csv
    csv_path = Rails.root.join('db', 'seeds', 'olx_categories.csv')

    unless File.exist?(csv_path)
      logger.warn "  ! CSV file not found: #{csv_path}"
      return { success: false, created: 0, updated: 0, error: 'CSV file not found' }
    end

    require 'csv'

    created_count = 0
    updated_count = 0
    total_count = 0
    parent_mappings = [] # Store [external_id, parent_external_id] for second pass

    # First pass: create/update all categories WITHOUT parent relationships
    CSV.foreach(csv_path, headers: true) do |row|
      total_count += 1
      external_id = row['external_id'].to_i
      name = row['name']
      slug = row['slug']
      # Support both old 'parent_id' column and new 'parent_external_id' column
      parent_external_id = row['parent_external_id'].present? ? row['parent_external_id'].to_i : (row['parent_id'].present? ? row['parent_id'].to_i : nil)
      has_shipping = row['has_shipping'] == '1' || row['has_shipping'] == 'true'
      has_brand = row['has_brand'] == '1' || row['has_brand'] == 'true'

      # Store parent mapping for second pass
      parent_mappings << [external_id, parent_external_id] if parent_external_id

      # Parse metadata
      metadata = nil
      if row['metadata'].present?
        begin
          metadata_str = row['metadata']
          metadata_str = metadata_str[1..-2] if metadata_str.start_with?('"') && metadata_str.end_with?('"')
          metadata_str = metadata_str.gsub('""', '"')
          metadata = metadata_str
        rescue => e
          logger.debug "  Could not parse metadata for category #{external_id}: #{e.message}"
        end
      end

      category = OlxCategory.find_or_initialize_by(external_id: external_id)

      if category.new_record?
        category.name = name
        category.slug = slug
        category.has_shipping = has_shipping
        category.has_brand = has_brand
        category.metadata = metadata
        category.save!
        created_count += 1
        logger.debug "    ✓ Created category: #{name} (ID: #{external_id})"
      else
        category.update!(
          name: name,
          slug: slug,
          has_shipping: has_shipping,
          has_brand: has_brand,
          metadata: metadata
        )
        updated_count += 1
        logger.debug "    ✓ Updated category: #{name} (ID: #{external_id})"
      end
    end

    # Second pass: update parent relationships
    # Build lookup of external_id -> database_id
    external_to_db_id = OlxCategory.pluck(:external_id, :id).to_h

    parent_mappings.each do |external_id, parent_external_id|
      category = OlxCategory.find_by(external_id: external_id)
      next unless category

      parent_db_id = external_to_db_id[parent_external_id]
      if parent_db_id && category.parent_id != parent_db_id
        category.update_column(:parent_id, parent_db_id)
        logger.debug "    ✓ Set parent for #{category.name}: #{parent_external_id} -> DB ID #{parent_db_id}"
      end
    end

    logger.info "  ✓ Imported #{total_count} categories from CSV (#{created_count} created, #{updated_count} updated)"

    { success: true, total: total_count, created: created_count, updated: updated_count }
  rescue => e
    logger.error "  ✗ Failed to import categories from CSV: #{e.message}"
    { success: false, created: 0, updated: 0, error: e.message }
  end

  ##
  # Import category attributes from CSV seed file
  #
  # @return [Hash] Result with created/updated counts
  #
  def import_attributes_from_csv
    csv_path = Rails.root.join('db', 'seeds', 'olx_category_attributes.csv')

    unless File.exist?(csv_path)
      logger.warn "  ! CSV file not found: #{csv_path}"
      return { success: false, created: 0, updated: 0, error: 'CSV file not found' }
    end

    require 'csv'

    created_count = 0
    updated_count = 0
    skipped_count = 0
    total_count = 0

    # Build a lookup of categories by external_id for faster processing
    category_lookup = OlxCategory.pluck(:external_id, :id).to_h

    CSV.foreach(csv_path, headers: true) do |row|
      total_count += 1
      external_id = row['external_id'].present? ? row['external_id'].to_i : nil
      category_external_id = row['category_external_id'].to_i
      name = row['name']
      attribute_type = row['attribute_type']
      input_type = row['input_type']
      required = row['required'] == '1' || row['required'] == 'true'

      # Parse options - handle double-escaped JSON from SQLite export
      options = nil
      if row['options'].present?
        begin
          options_str = row['options']
          options_str = options_str[1..-2] if options_str.start_with?('"') && options_str.end_with?('"')
          options_str = options_str.gsub('""', '"')
          options = options_str
        rescue => e
          logger.debug "  Could not parse options for attribute #{name}: #{e.message}"
        end
      end

      # Find the category
      category_id = category_lookup[category_external_id]
      unless category_id
        skipped_count += 1
        logger.debug "  ! Skipping attribute #{name}: category #{category_external_id} not found"
        next
      end

      # Find or create attribute
      attribute = if external_id
        OlxCategoryAttribute.find_or_initialize_by(olx_category_id: category_id, external_id: external_id)
      else
        OlxCategoryAttribute.find_or_initialize_by(olx_category_id: category_id, name: name)
      end

      if attribute.new_record?
        attribute.external_id = external_id
        attribute.name = name
        attribute.attribute_type = attribute_type
        attribute.input_type = input_type
        attribute.required = required
        attribute.options = options
        attribute.save!
        created_count += 1
        logger.debug "    ✓ Created attribute: #{name} for category #{category_external_id}"
      else
        attribute.update!(
          name: name,
          attribute_type: attribute_type,
          input_type: input_type,
          required: required,
          options: options
        )
        updated_count += 1
        logger.debug "    ✓ Updated attribute: #{name} for category #{category_external_id}"
      end
    end

    logger.info "  ✓ Imported #{total_count} attributes from CSV (#{created_count} created, #{updated_count} updated, #{skipped_count} skipped)"

    { success: true, total: total_count, created: created_count, updated: updated_count, skipped: skipped_count }
  rescue => e
    logger.error "  ✗ Failed to import attributes from CSV: #{e.message}"
    { success: false, created: 0, updated: 0, error: e.message }
  end

  ##
  # Import category templates from CSV seed file
  #
  # @return [Hash] Result with created/updated counts
  #
  def import_templates_from_csv
    csv_path = Rails.root.join('db', 'seeds', 'olx_category_templates.csv')

    unless File.exist?(csv_path)
      logger.warn "  ! CSV file not found: #{csv_path}"
      return { success: false, created: 0, updated: 0, error: 'CSV file not found' }
    end

    require 'csv'

    created_count = 0
    updated_count = 0
    skipped_count = 0
    total_count = 0

    # Build lookups for categories and locations
    category_lookup = OlxCategory.pluck(:external_id, :id).to_h
    location_lookup = OlxLocation.pluck(:external_id, :id).to_h

    CSV.foreach(csv_path, headers: true) do |row|
      total_count += 1
      name = row['name']
      category_external_id = row['category_external_id'].to_i
      location_external_id = row['location_external_id'].present? ? row['location_external_id'].to_i : nil
      default_listing_type = row['default_listing_type']
      default_state = row['default_state']
      title_template = row['title_template']
      description_template = row['description_template']

      # Parse JSON fields - Ruby CSV handles escaping properly
      attribute_mappings = nil
      if row['attribute_mappings'].present?
        begin
          attribute_mappings = JSON.parse(row['attribute_mappings'])
        rescue => e
          logger.debug "  Could not parse attribute_mappings for template #{name}: #{e.message}"
        end
      end

      description_filter = nil
      if row['description_filter'].present?
        begin
          description_filter = JSON.parse(row['description_filter'])
        rescue => e
          logger.debug "  Could not parse description_filter for template #{name}: #{e.message}"
        end
      end

      # Find the category
      category_id = category_lookup[category_external_id]
      unless category_id
        skipped_count += 1
        logger.debug "  ! Skipping template #{name}: category #{category_external_id} not found"
        next
      end

      # Find the location (optional)
      location_id = location_external_id ? location_lookup[location_external_id] : nil

      # Find or create template for this shop
      template = shop.olx_category_templates.find_or_initialize_by(
        name: name,
        olx_category_id: category_id
      )

      if template.new_record?
        template.olx_location_id = location_id
        template.default_listing_type = default_listing_type
        template.default_state = default_state
        template.attribute_mappings = attribute_mappings
        template.description_filter = description_filter
        template.title_template = title_template
        template.description_template = description_template
        template.save!
        created_count += 1
        logger.debug "    ✓ Created template: #{name}"
      else
        template.update!(
          olx_location_id: location_id,
          default_listing_type: default_listing_type,
          default_state: default_state,
          attribute_mappings: attribute_mappings,
          description_filter: description_filter,
          title_template: title_template,
          description_template: description_template
        )
        updated_count += 1
        logger.debug "    ✓ Updated template: #{name}"
      end
    end

    logger.info "  ✓ Imported #{total_count} templates from CSV (#{created_count} created, #{updated_count} updated, #{skipped_count} skipped)"

    { success: true, total: total_count, created: created_count, updated: updated_count, skipped: skipped_count }
  rescue => e
    logger.error "  ✗ Failed to import templates from CSV: #{e.message}"
    { success: false, created: 0, updated: 0, error: e.message }
  end
end
