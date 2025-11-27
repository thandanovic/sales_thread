# frozen_string_literal: true

##
# OlxSyncService
#
# Service for syncing products from OLX to the local shop database.
# Fetches all listings from OLX and creates/updates local Product records.
#
class OlxSyncService
  attr_reader :shop, :sync_logger

  def initialize(shop)
    @shop = shop
    @sync_logger = setup_sync_logger
  end

  private

  ##
  # Setup dedicated logger for sync operations
  #
  def setup_sync_logger
    log_dir = Rails.root.join('log', 'olx_sync')
    FileUtils.mkdir_p(log_dir) unless Dir.exist?(log_dir)

    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    log_file = log_dir.join("sync_shop_#{shop.id}_#{timestamp}.log")

    logger = Logger.new(log_file)
    logger.formatter = proc do |severity, datetime, progname, msg|
      "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
    end
    logger
  end

  public

  ##
  # Sync all products from OLX to the shop
  #
  # @param limit [Integer] Maximum number of products to sync (default: 10 for testing)
  # @param status_filter [Array<String>] Only sync listings with these statuses (default: ['active'])
  # @param category_ids [Array<Integer>] Only sync listings from these category IDs (optional)
  # @param skip_existing [Boolean] If true, skip already synced products instead of updating them (default: false)
  # @return [Hash] Result hash with counts: { success: true, imported: 5, updated: 3, skipped: 2 }
  #
  def sync_products(limit: 10, status_filter: ['active'], category_ids: nil, skip_existing: false)
    sync_logger.info "=" * 80
    sync_logger.info "Starting OLX Sync for Shop ##{shop.id} - #{shop.name}"
    sync_logger.info "Limit: #{limit} products"
    sync_logger.info "Status Filter: #{status_filter.join(', ')}" if status_filter.present?
    sync_logger.info "Category Filter: #{category_ids.join(', ')}" if category_ids.present?
    sync_logger.info "Skip Existing: #{skip_existing ? 'YES (only import new)' : 'NO (update existing)'}"
    sync_logger.info "=" * 80

    Rails.logger.info "[OLX Sync] Starting sync for shop #{shop.id} (limit: #{limit})"

    # Ensure authenticated
    sync_logger.info "Step 1: Authenticating with OLX API..."
    OlxApiService.ensure_authenticated!(shop)
    sync_logger.info "✓ Authentication successful"

    # Fetch all listings from OLX
    sync_logger.info "Step 2: Fetching listings from OLX..."
    olx_listings = fetch_all_listings(limit: limit)

    if olx_listings.empty?
      sync_logger.info "No listings found on OLX"
      Rails.logger.info "[OLX Sync] No listings found on OLX"
      return { success: true, imported: 0, updated: 0, skipped: 0 }
    end

    sync_logger.info "✓ Found #{olx_listings.length} listings on OLX"
    Rails.logger.info "[OLX Sync] Found #{olx_listings.length} listings on OLX"

    imported_count = 0
    updated_count = 0
    skipped_count = 0
    failed_count = 0

    sync_logger.info ""
    sync_logger.info "Step 3: Processing listings..."
    sync_logger.info "-" * 80

    olx_listings.each_with_index do |listing, index|
      sync_logger.info ""
      sync_logger.info "Processing listing #{index + 1}/#{olx_listings.length}:"
      sync_logger.info "  OLX ID: #{listing['id']}"
      sync_logger.info "  Title: #{listing['title']}"
      sync_logger.info "  Price: #{listing['price']} #{listing['currency']}"
      sync_logger.info "  Status: #{listing['status']}"

      # Apply status filter
      if status_filter.present? && !status_filter.include?(listing['status'])
        sync_logger.info "  ⊘ FILTERED: Status '#{listing['status']}' not in filter #{status_filter.inspect}"
        skipped_count += 1
        next
      end

      # Apply category filter (requires fetching full listing first)
      if category_ids.present?
        # Need to fetch full listing to get category_id
        full_listing = fetch_full_listing_details(listing['id'])
        if full_listing && !category_ids.include?(full_listing['category_id'])
          sync_logger.info "  ⊘ FILTERED: Category ID #{full_listing['category_id']} not in filter #{category_ids.inspect}"
          skipped_count += 1
          next
        end
      end

      Rails.logger.info "[OLX Sync] Processing listing #{index + 1}/#{olx_listings.length}: #{listing['id']}"

      begin
        result = sync_single_listing(listing, skip_existing: skip_existing)

        case result
        when :created
          imported_count += 1
          sync_logger.info "  ✓ Result: NEW product created"
        when :updated
          updated_count += 1
          sync_logger.info "  ✓ Result: EXISTING product updated"
        when :skipped
          skipped_count += 1
          sync_logger.info "  ⊘ Result: SKIPPED"
        when :failed
          failed_count += 1
          sync_logger.info "  ✗ Result: FAILED"
        end
      rescue => e
        failed_count += 1
        sync_logger.error "  ✗ EXCEPTION: #{e.class} - #{e.message}"
        sync_logger.error "  Backtrace: #{e.backtrace.first(3).join(' | ')}"
        Rails.logger.error "[OLX Sync] Error syncing listing #{listing['id']}: #{e.message}"
      end
    end

    sync_logger.info ""
    sync_logger.info "-" * 80
    sync_logger.info "Sync completed successfully!"
    sync_logger.info "Summary:"
    sync_logger.info "  - New products imported: #{imported_count}"
    sync_logger.info "  - Existing products updated: #{updated_count}"
    sync_logger.info "  - Skipped: #{skipped_count}"
    sync_logger.info "  - Failed: #{failed_count}"
    sync_logger.info "  - Total processed: #{olx_listings.length}"
    sync_logger.info "=" * 80

    Rails.logger.info "[OLX Sync] Completed: #{imported_count} imported, #{updated_count} updated, #{skipped_count} skipped, #{failed_count} failed"

    {
      success: true,
      imported: imported_count,
      updated: updated_count,
      skipped: skipped_count,
      failed: failed_count
    }
  rescue => e
    sync_logger.error ""
    sync_logger.error "=" * 80
    sync_logger.error "SYNC FAILED!"
    sync_logger.error "Error: #{e.class} - #{e.message}"
    sync_logger.error "Backtrace:"
    e.backtrace.first(10).each { |line| sync_logger.error "  #{line}" }
    sync_logger.error "=" * 80

    Rails.logger.error "[OLX Sync] Failed: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
    { success: false, error: e.message }
  end

  private

  ##
  # Fetch all listings from OLX API (authenticated user's listings only)
  #
  # @param limit [Integer] Maximum number of listings to fetch
  # @return [Array<Hash>] Array of listing objects
  #
  def fetch_all_listings(limit: nil)
    # Ensure shop has user info
    if shop.olx_user_name.blank?
      sync_logger.error "  ✗ Shop missing OLX user info. Re-authenticating..."
      OlxApiService.authenticate(shop)
      shop.reload
    end

    unless shop.olx_user_name.present?
      sync_logger.error "  ✗ Cannot fetch listings: OLX username not available"
      raise "OLX username not available after authentication"
    end

    sync_logger.info "  Fetching listings for user: #{shop.olx_user_name}"

    all_listings = []
    page = 1
    per_page = 50

    loop do
      sync_logger.info "  Fetching page #{page}..."
      Rails.logger.info "[OLX Sync] Fetching page #{page} for user #{shop.olx_user_name}"

      # Use the user-specific listings endpoint
      endpoint = "/users/#{shop.olx_user_name}/listings"
      response = OlxApiService.get(endpoint, shop, { page: page, per_page: per_page })

      listings = response['data'] || response['listings'] || []

      # Apply limit if specified
      if limit && (all_listings.length + listings.length) > limit
        remaining = limit - all_listings.length
        listings = listings.first(remaining)
      end

      all_listings.concat(listings)

      sync_logger.info "  ✓ Page #{page}: #{listings.length} listings fetched (total: #{all_listings.length})"
      Rails.logger.info "[OLX Sync] Page #{page}: #{listings.length} listings (total: #{all_listings.length})"

      # Stop if we've reached the limit
      break if limit && all_listings.length >= limit

      # Check if there are more pages
      total_pages = response['meta']&.dig('last_page') || response['total_pages']
      break if listings.empty? || (total_pages && page >= total_pages)

      page += 1
    end

    all_listings
  rescue => e
    sync_logger.error "  ✗ Error fetching listings: #{e.message}"
    Rails.logger.error "[OLX Sync] Error fetching listings: #{e.message}"
    []
  end

  ##
  # Sync a single listing from OLX to local database
  #
  # @param listing [Hash] OLX listing data (summary from list)
  # @return [Symbol] :created, :updated, or :skipped
  #
  def sync_single_listing(listing, skip_existing: false)
    external_id = listing['id'].to_s

    # Quick check: if skip_existing is true, check if we already have this listing
    if skip_existing
      existing_check = shop.olx_listings.find_by(external_listing_id: external_id)
      if existing_check
        sync_logger.info "  ⊘ Already synced - skipping (product ID: #{existing_check.product_id})"
        Rails.logger.info "[OLX Sync] Skipping already synced listing #{external_id}"
        return :skipped
      end
    end

    sync_logger.info "  Fetching full listing details from OLX API..."

    # Fetch full listing details including all attributes, category, location, etc.
    full_listing = fetch_full_listing_details(external_id)

    unless full_listing
      sync_logger.error "  ✗ Failed to fetch full listing details from API"
      return :failed
    end

    # Extract all data from full listing
    title = full_listing['title'] || listing['title']
    # Description is in additional['description'] for OLX.ba API
    description = full_listing.dig('additional', 'description') ||
                  full_listing['description'] ||
                  full_listing['short_description'] ||
                  listing['description']
    price = (full_listing['price'] || listing['price'])&.to_f || 0.0
    currency = full_listing['currency'] || listing['currency'] || 'BAM'
    status = full_listing['status'] || listing['status']

    # Extract OLX-specific data
    category_id = full_listing['category_id']
    city_id = full_listing['city_id'] || full_listing['location_id'] || full_listing.dig('location', 'id')
    listing_type = full_listing['listing_type'] || 'sell'
    state = full_listing['state'] || full_listing['condition']
    attributes = full_listing['attributes'] || []

    # Debug: Log if city_id is missing
    if city_id.blank?
      sync_logger.warn "    ! City ID missing - checking response structure..."
      location_keys = full_listing.keys.grep(/location|city|region/i)
      if location_keys.any?
        sync_logger.warn "    ! Found location-related keys: #{location_keys.join(', ')}"
        location_keys.each do |key|
          sync_logger.warn "    ! #{key}: #{full_listing[key].inspect}"
        end
      else
        sync_logger.warn "    ! No location data found in API response"
      end
    end

    # Extract image URLs from full listing
    image_urls = extract_image_urls(full_listing)

    sync_logger.info "  Listing details:"
    sync_logger.info "    - Title: #{title}"
    sync_logger.info "    - Category ID: #{category_id}"
    sync_logger.info "    - City ID: #{city_id}"
    sync_logger.info "    - Listing Type: #{listing_type}"
    sync_logger.info "    - State: #{state}"
    sync_logger.info "    - Attributes: #{attributes.length}"
    sync_logger.info "    - Images: #{image_urls.length}" if image_urls.any?
    Rails.logger.info "[OLX Sync] Listing: #{title} (ID: #{external_id}, Status: #{status})"

    # Check if we already have this listing
    existing_listing = shop.olx_listings.find_by(external_listing_id: external_id)

    # Find or create category template for this OLX listing
    sync_logger.info "  Finding/creating category template..."
    category_template = find_or_create_category_template(category_id, city_id, listing_type, state)

    if category_template.nil?
      sync_logger.error "  ✗ Could not find/create category template - category or location missing from database"
      sync_logger.info "    Tip: You may need to fetch categories and locations from OLX first"
      return :skipped
    end

    if existing_listing
      # Update existing product
      product = existing_listing.product

      sync_logger.info "  Found existing product (ID: #{product.id})"
      sync_logger.info "    Updating product data..."
      Rails.logger.info "[OLX Sync] Found existing product #{product.id}"

      # Determine if product should be published based on OLX status
      is_published = ['active', 'published', 'live'].include?(status&.downcase)

      product.update!(
        title: title,
        description: description,
        price: price,
        currency: currency,
        source: 'olx',
        import_source: 'olx_sync',
        olx_ad_id: external_id,
        olx_title: title,
        olx_description: description,
        olx_category_template: category_template,
        image_urls: image_urls,
        published: is_published,
        updated_at: Time.current
      )

      sync_logger.info "    Updated: title, description (#{description.present? ? 'YES' : 'NO'}), price (#{price} #{currency}), published: #{is_published}, template: #{category_template.name}"

      # Download and attach images if available
      if image_urls.any?
        sync_logger.info "    Processing #{image_urls.length} images..."
        # Clear old images first
        product.images.purge if product.images.attached?
        download_images(product, image_urls)
      else
        sync_logger.info "    No images to download"
      end

      # Update OLX listing with full metadata
      existing_listing.update!(
        status: map_olx_status(status),
        metadata: full_listing,
        synced_at: Time.current
      )

      sync_logger.info "    Updated OLX listing:"
      sync_logger.info "      - Status: #{map_olx_status(status)}"
      sync_logger.info "      - Full metadata stored (category, location, attributes, etc.)"
      sync_logger.info "    Product ID: #{product.id}"
      Rails.logger.info "[OLX Sync] ✓ Updated product #{product.id}"
      :updated
    else
      # Create new product
      sync_logger.info "  No existing product found - creating new one..."

      # Determine if product should be published based on OLX status
      is_published = ['active', 'published', 'live'].include?(status&.downcase)

      sync_logger.info "    Product data:"
      sync_logger.info "      - Title: #{title}"
      sync_logger.info "      - Description: #{description.present? ? 'YES' : 'NO'}"
      sync_logger.info "      - Price: #{price} #{currency}"
      sync_logger.info "      - Images: #{image_urls.length}"
      sync_logger.info "      - Category Template: #{category_template.name}"
      sync_logger.info "      - Listing Type: #{listing_type}"
      sync_logger.info "      - State: #{state}"
      sync_logger.info "      - Source: olx"
      sync_logger.info "      - Import Source: olx_sync"
      sync_logger.info "      - OLX Ad ID: #{external_id}"
      sync_logger.info "      - Published: #{is_published}"
      sync_logger.info "      - Status: #{map_olx_status(status)}"

      product = shop.products.create!(
        title: title,
        description: description,
        price: price,
        currency: currency,
        source: 'olx',
        import_source: 'olx_sync',
        source_id: external_id,
        olx_ad_id: external_id,
        olx_title: title,
        olx_description: description,
        olx_category_template: category_template,
        image_urls: image_urls,
        margin: 0.0,
        published: is_published
      )

      sync_logger.info "    ✓ Product created (ID: #{product.id})"

      # Download and attach images if available
      if image_urls.any?
        sync_logger.info "    Downloading #{image_urls.length} images..."
        download_images(product, image_urls)
      else
        sync_logger.info "    No images to download"
      end

      # Create OLX listing record to track relationship with full metadata
      shop.olx_listings.create!(
        product: product,
        external_listing_id: external_id,
        status: map_olx_status(status),
        metadata: full_listing,
        published_at: (Time.current if is_published),
        synced_at: Time.current
      )

      sync_logger.info "    ✓ OLX listing record created:"
      sync_logger.info "      - External ID: #{external_id}"
      sync_logger.info "      - Status: #{map_olx_status(status)}"
      sync_logger.info "      - Full metadata stored (category_id: #{category_id}, city_id: #{city_id}, attributes: #{attributes.length})"
      Rails.logger.info "[OLX Sync] ✓ Created product #{product.id}"
      :created
    end
  rescue => e
    sync_logger.error "    ✗ Failed to sync: #{e.class} - #{e.message}"
    sync_logger.error "    Backtrace: #{e.backtrace.first(3).join(' | ')}" if e.backtrace
    Rails.logger.error "[OLX Sync] Error syncing listing #{external_id}: #{e.class} - #{e.message}"
    :failed
  end

  ##
  # Fetch full listing details from OLX API
  #
  # @param listing_id [String] External listing ID
  # @return [Hash, nil] Full listing data or nil if failed
  #
  def fetch_full_listing_details(listing_id)
    sync_logger.info "    Fetching from GET /listings/#{listing_id}..."
    response = OlxApiService.get("/listings/#{listing_id}", shop)
    sync_logger.info "    ✓ Full listing data retrieved"
    response
  rescue => e
    sync_logger.error "    ✗ Failed to fetch full listing: #{e.message}"
    Rails.logger.error "[OLX Sync] Failed to fetch listing #{listing_id}: #{e.message}"
    nil
  end

  ##
  # Find or create category template for OLX category and location
  #
  # @param category_id [Integer] OLX category ID
  # @param city_id [Integer] OLX city/location ID
  # @param listing_type [String] Listing type (sell, rent, etc.)
  # @param state [String] Item state (new, used, etc.)
  # @return [OlxCategoryTemplate, nil] Template or nil if category/location not found
  #
  def find_or_create_category_template(category_id, city_id, listing_type, state)
    return nil unless category_id

    # Find or create OLX category
    olx_category = OlxCategory.find_by(external_id: category_id)
    unless olx_category
      sync_logger.warn "    ! Category #{category_id} not found in local database"
      return nil
    end

    # Find or create OLX location (optional - may not exist for GPS-based listings)
    olx_location = nil
    if city_id.present?
      olx_location = OlxLocation.find_by(external_id: city_id)
      unless olx_location
        sync_logger.warn "    ! Location #{city_id} not found in local database (using category only)"
      end
    else
      sync_logger.info "    ! No city_id provided (OLX uses GPS coordinates) - creating template with category only"
    end

    # Find existing template or create new one
    # Location is now optional - template can exist with just category
    template = shop.olx_category_templates.find_or_create_by!(
      olx_category: olx_category,
      olx_location: olx_location
    ) do |t|
      if olx_location
        t.name = "#{olx_category.name} - #{olx_location.name} (Auto-created from sync)"
      else
        t.name = "#{olx_category.name} - No Location (Auto-created from sync)"
      end
      t.default_listing_type = listing_type || 'sell'
      t.default_state = state || 'used'
      sync_logger.info "    ✓ Created new category template: #{t.name}"
    end

    sync_logger.info "    Using template: #{template.name} (ID: #{template.id})"
    template
  rescue => e
    sync_logger.error "    ✗ Failed to find/create category template: #{e.message}"
    Rails.logger.error "[OLX Sync] Template error: #{e.message}"
    nil
  end

  ##
  # Extract image URLs from OLX listing data
  #
  # @param listing [Hash] OLX listing data
  # @return [Array<String>] Array of image URLs
  #
  def extract_image_urls(listing)
    # OLX API might have different formats for images
    # Try different possible keys
    images = listing['images'] || listing['photos'] || listing['pictures'] || []

    # Handle different formats: array of URLs or array of hashes with url key
    return [] if images.blank?

    images.map do |img|
      case img
      when String
        img
      when Hash
        img['url'] || img['link'] || img['original'] || img['large'] || img['medium']
      else
        nil
      end
    end.compact
  end

  ##
  # Download and attach images to product
  #
  # @param product [Product] Product to attach images to
  # @param image_urls [Array<String>] Array of image URLs
  #
  def download_images(product, image_urls)
    require 'open-uri'

    success_count = 0
    image_urls.each_with_index do |url, index|
      next if url.blank?

      begin
        sync_logger.info "      Downloading image #{index + 1}/#{image_urls.length}..."

        io = URI.open(url)
        filename = "olx_#{product.id || 'new'}_#{index}#{File.extname(url.split('?').first)}"

        product.images.attach(
          io: io,
          filename: filename,
          content_type: io.content_type || 'image/jpeg'
        )

        success_count += 1
        sync_logger.info "      ✓ Image #{index + 1} downloaded"
      rescue OpenURI::HTTPError => e
        sync_logger.error "      ✗ Failed to download image #{index + 1}: HTTP #{e.message}"
      rescue => e
        sync_logger.error "      ✗ Failed to download image #{index + 1}: #{e.message}"
      end
    end

    sync_logger.info "    ✓ Downloaded #{success_count}/#{image_urls.length} images"
  rescue => e
    sync_logger.error "    ✗ Failed to process images: #{e.message}"
    # Don't fail the entire sync if images fail
  end

  ##
  # Map OLX status to our internal status
  #
  # @param olx_status [String] OLX status string
  # @return [String] Internal status
  #
  def map_olx_status(olx_status)
    case olx_status&.downcase
    when 'active', 'published', 'live'
      'published'
    when 'draft', 'inactive'
      'draft'
    else
      'draft'
    end
  end
end
