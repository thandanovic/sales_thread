# frozen_string_literal: true

##
# ScraperService
#
# Ruby service that bridges Rails with Playwright scraper scripts.
# Executes Node.js Playwright scripts and imports the results.
#
# Usage:
#   # Test login
#   ScraperService.test_login(username: 'user@example.com', password: 'secret')
#
#   # Scrape products
#   products = ScraperService.scrape_products(max_products: 10)
#
#   # Import scraped data
#   ScraperService.import_from_json('scraper/data/products-123456.json', shop)
#
require 'open-uri'

class ScraperService
  class ScraperError < StandardError; end
  class LoginError < ScraperError; end
  class ScrapeError < ScraperError; end

  SCRAPER_DIR = Rails.root.join('scraper')
  DATA_DIR = SCRAPER_DIR.join('data')
  ENV_FILE = SCRAPER_DIR.join('.env')
  LOG_DIR = Rails.root.join('log', 'scraper')

  # Setup dedicated logger for scraper operations
  def self.logger
    @logger ||= begin
      FileUtils.mkdir_p(LOG_DIR)
      log_file = LOG_DIR.join("scraper-#{Date.today.strftime('%Y%m%d')}.log")
      logger = Logger.new(log_file, 'daily')
      logger.formatter = proc do |severity, datetime, progname, msg|
        "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
      end
      logger
    end
  end

  ##
  # Test login to Intercars and save session cookies
  #
  # @param username [String] Intercars username/email
  # @param password [String] Intercars password
  # @param headless [Boolean] Run browser in headless mode
  # @return [Hash] Result with status and message
  #
  def self.test_login(username:, password:, headless: true)
    ensure_setup!
    create_env_file(username: username, password: password, headless: headless)

    logger.info "Testing login for #{username}"

    result = execute_script('test-login', timeout: 60)

    if result[:success]
      # Check if cookies were saved
      cookies_file = DATA_DIR.join('session-cookies.json')
      if cookies_file.exist?
        { success: true, message: 'Login successful, session saved' }
      else
        { success: false, message: 'Login failed - no session cookies saved' }
      end
    else
      { success: false, message: result[:error], output: result[:output] }
    end
  end

  ##
  # Scrape products from Intercars catalog
  #
  # @param max_products [Integer] Maximum number of products to scrape
  # @param headless [Boolean] Run browser in headless mode
  # @param username [String] Optional username (scrape.js handles login inline)
  # @param password [String] Optional password (scrape.js handles login inline)
  # @param product_url [String] Optional product URL to scrape
  # @return [Hash] Result with products data or error
  #
  def self.scrape_products(max_products: 10, headless: true, username: nil, password: nil, product_url: nil)
    ensure_setup!

    # Note: Our updated scrape.js handles login inline, so we don't need session cookies anymore
    # We'll pass credentials directly to the script

    logger.info "=" * 80
    logger.info "Starting product scrape (max: #{max_products})"
    logger.info "Product URL: #{product_url}" if product_url
    logger.info "Headless: #{headless}"

    # Set environment with all needed variables
    env_vars = { MAX_PRODUCTS: max_products, HEADLESS: headless }
    env_vars[:INTERCARS_USERNAME] = username if username
    env_vars[:INTERCARS_PASSWORD] = password if password
    env_vars[:PRODUCT_URL] = product_url if product_url

    update_env(env_vars)

    result = execute_script('scrape', timeout: max_products * 10)

    if result[:success]
      # Find the latest products JSON file
      json_file = latest_products_file

      if json_file
        products = JSON.parse(File.read(json_file))
        logger.info "✓ Scraped #{products.length} products successfully"
        logger.info "JSON file: #{json_file}"

        # Log extraction stats
        with_images = products.count { |p| p['images']&.any? }
        with_specs = products.count { |p| p['specs'].present? }
        with_brand = products.count { |p| p['brand'].present? }

        logger.info "Extraction stats:"
        logger.info "  - Products with images: #{with_images}/#{products.length}"
        logger.info "  - Products with specs: #{with_specs}/#{products.length}"
        logger.info "  - Products with brand: #{with_brand}/#{products.length}"

        {
          success: true,
          products: products,
          file: json_file.to_s,
          count: products.length
        }
      else
        logger.error "Scraping completed but no data file found"
        {
          success: false,
          message: 'Scraping completed but no data file found'
        }
      end
    else
      logger.error "Scraping failed: #{result[:error]}"
      {
        success: false,
        message: result[:error],
        output: result[:output]
      }
    end
  end

  ##
  # Import products from scraped JSON file into database
  #
  # @param file_path [String] Path to JSON file
  # @param shop [Shop] Shop to import products into
  # @param import_log [ImportLog] Optional import log to track progress
  # @return [Hash] Result with imported count and errors
  #
  def self.import_from_json(file_path, shop, import_log: nil)
    products_data = JSON.parse(File.read(file_path))

    imported = 0
    errors = []

    products_data.each_with_index do |product_data, index|
      begin
        import_product(product_data, shop, import_log)
        imported += 1
      rescue => e
        error_msg = "Product #{index + 1}: #{e.message}"
        errors << error_msg
        Rails.logger.error "[Scraper Import] #{error_msg}"

        # Create ImportedProduct record for failed import
        if import_log.present?
          ImportedProduct.create!(
            shop: shop,
            import_log: import_log,
            source: 'intercars',
            raw_data: product_data.to_json,
            status: 'error',
            error_text: e.message
          )
          import_log.increment!(:failed_rows)
          import_log.increment!(:processed_rows)
        end
      end
    end

    {
      success: true,
      imported: imported,
      total: products_data.length,
      errors: errors
    }
  end

  ##
  # Get existing source_ids for a shop to skip re-scraping
  #
  # @param shop [Shop] Shop to query
  # @return [Array<String>] List of existing source_ids
  #
  def self.existing_source_ids(shop)
    shop.products.where(source: 'intercars').pluck(:source_id).compact
  end

  ##
  # Scrape and import in one step
  #
  # @param shop [Shop] Shop to import into
  # @param username [String] Intercars username
  # @param password [String] Intercars password
  # @param product_url [String] URL of the page to scrape
  # @param max_products [Integer] Max products to scrape
  # @param import_log [ImportLog] Optional import log
  # @return [Hash] Result with scraping and import info
  #
  def self.scrape_and_import(shop, username: nil, password: nil, product_url: nil, max_products: 10, import_log: nil)
    # Our updated scrape.js handles login inline, so we skip the separate test_login step
    # and pass credentials directly to scrape_products

    unless username && password
      return {
        success: false,
        error: "Username and password are required",
        total: 0,
        imported: 0,
        failed: 0
      }
    end

    # Update import log to scraping phase
    if import_log.present?
      import_log.update!(current_phase: 'scraping', scraped_count: 0)
    end

    # Get existing source_ids to skip re-scraping images/tech description
    existing_ids = existing_source_ids(shop)
    logger.info "Found #{existing_ids.length} existing products - will skip image/tech scraping for these"

    # Scrape with credentials and progress tracking
    scrape_result = scrape_products_with_progress(
      max_products: max_products,
      username: username,
      password: password,
      product_url: product_url,
      headless: true,
      import_log: import_log,
      existing_source_ids: existing_ids
    )

    unless scrape_result[:success]
      return {
        success: false,
        error: scrape_result[:message] || 'Scraping failed',
        total: 0,
        imported: 0,
        failed: 0
      }
    end

    # Update to importing phase
    if import_log.present?
      import_log.update!(current_phase: 'importing', total_rows: scrape_result[:count])
    end

    # Import
    import_result = import_from_json(
      scrape_result[:file],
      shop,
      import_log: import_log
    )

    # Mark as complete
    if import_log.present?
      import_log.update!(current_phase: 'completed')
    end

    {
      success: true,
      scraped: scrape_result[:count],
      imported: import_result[:imported],
      total: scrape_result[:count],
      failed: scrape_result[:count] - import_result[:imported],
      errors: import_result[:errors],
      file: scrape_result[:file]
    }
  end

  ##
  # Scrape products with progress tracking
  # Monitors the scraper log file to update progress in import_log
  #
  def self.scrape_products_with_progress(max_products:, username:, password:, product_url:, headless:, import_log: nil, existing_source_ids: [])
    ensure_setup!

    logger.info "=" * 80
    logger.info "Starting product scrape (max: #{max_products})"
    logger.info "Product URL: #{product_url}" if product_url
    logger.info "Headless: #{headless}"
    logger.info "Existing source_ids to skip: #{existing_source_ids.length}"

    # Set environment with all needed variables
    env_vars = { MAX_PRODUCTS: max_products, HEADLESS: headless }
    env_vars[:INTERCARS_USERNAME] = username if username
    env_vars[:INTERCARS_PASSWORD] = password if password
    env_vars[:PRODUCT_URL] = product_url if product_url

    # Pass existing source_ids to skip re-scraping (comma-separated)
    if existing_source_ids.any?
      env_vars[:EXISTING_SOURCE_IDS] = existing_source_ids.join(',')
    end

    update_env(env_vars)

    # Execute with progress monitoring
    result = execute_script_with_progress('scrape', timeout: max_products * 30, import_log: import_log, max_products: max_products)

    if result[:success]
      # Find the latest products JSON file
      json_file = latest_products_file

      if json_file
        products = JSON.parse(File.read(json_file))
        logger.info "✓ Scraped #{products.length} products successfully"
        logger.info "JSON file: #{json_file}"

        # Log extraction stats
        with_images = products.count { |p| p['images']&.any? }
        with_specs = products.count { |p| p['specs'].present? }
        with_brand = products.count { |p| p['brand'].present? }

        logger.info "Extraction stats:"
        logger.info "  - Products with images: #{with_images}/#{products.length}"
        logger.info "  - Products with specs: #{with_specs}/#{products.length}"
        logger.info "  - Products with brand: #{with_brand}/#{products.length}"

        {
          success: true,
          products: products,
          file: json_file.to_s,
          count: products.length
        }
      else
        logger.error "Scraping completed but no data file found"
        {
          success: false,
          message: 'Scraping completed but no data file found'
        }
      end
    else
      logger.error "Scraping failed: #{result[:error]}"
      {
        success: false,
        message: result[:error],
        output: result[:output]
      }
    end
  end

  ##
  # Run investigation script to analyze site structure
  #
  # @return [Hash] Result with analysis info
  #
  def self.investigate
    ensure_setup!

    Rails.logger.info "[Scraper] Running site investigation"

    result = execute_script('investigate', timeout: 60)

    if result[:success]
      { success: true, output: result[:output] }
    else
      { success: false, message: result[:error], output: result[:output] }
    end
  end

  ##
  # Check if scraper is set up correctly
  #
  # @return [Boolean]
  #
  def self.setup?
    SCRAPER_DIR.exist? &&
      SCRAPER_DIR.join('package.json').exist? &&
      SCRAPER_DIR.join('node_modules').exist?
  end

  ##
  # Check if there's a valid session
  #
  # @return [Boolean]
  #
  def self.session_valid?
    cookies_file = DATA_DIR.join('session-cookies.json')
    cookies_file.exist? && cookies_file.mtime > 1.day.ago
  end

  private

  def self.ensure_setup!
    unless SCRAPER_DIR.exist?
      raise ScraperError, 'Scraper directory not found'
    end

    unless SCRAPER_DIR.join('package.json').exist?
      raise ScraperError, 'package.json not found. Run: cd scraper && npm install'
    end

    unless SCRAPER_DIR.join('node_modules').exist?
      raise ScraperError, 'Node modules not installed. Run: cd scraper && npm install'
    end
  end

  def self.execute_script(script_name, timeout: 120)
    script_file = SCRAPER_DIR.join("#{script_name}.js")

    unless script_file.exist?
      return { success: false, error: "Script not found: #{script_name}.js" }
    end

    cmd = "cd #{SCRAPER_DIR} && node #{script_name}.js"

    output = []
    error_output = []
    success = false

    begin
      Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
        stdin.close

        # Collect output with timeout
        timeout_at = Time.now + timeout

        until stdout.eof? && stderr.eof?
          break if Time.now > timeout_at

          if IO.select([stdout, stderr], nil, nil, 1)
            begin
              output << stdout.read_nonblock(4096) if stdout.ready?
            rescue EOFError, IO::WaitReadable
            end

            begin
              error_output << stderr.read_nonblock(4096) if stderr.ready?
            rescue EOFError, IO::WaitReadable
            end
          end
        end

        exit_status = wait_thr.value
        success = exit_status.success?
      end

      full_output = (output + error_output).join

      if success
        { success: true, output: full_output }
      else
        { success: false, error: 'Script execution failed', output: full_output }
      end

    rescue => e
      { success: false, error: e.message, output: '' }
    end
  end

  ##
  # Execute script with progress monitoring
  # Parses output to track scraping progress and updates import_log
  #
  def self.execute_script_with_progress(script_name, timeout: 120, import_log: nil, max_products: 10)
    script_file = SCRAPER_DIR.join("#{script_name}.js")

    unless script_file.exist?
      return { success: false, error: "Script not found: #{script_name}.js" }
    end

    cmd = "cd #{SCRAPER_DIR} && node #{script_name}.js"

    output = []
    error_output = []
    success = false
    last_progress_update = Time.now
    last_scraped_count = 0

    begin
      Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
        stdin.close

        # Collect output with timeout
        timeout_at = Time.now + timeout

        until stdout.eof? && stderr.eof?
          if Time.now > timeout_at
            # Kill the process on timeout
            Process.kill('TERM', wait_thr.pid) rescue nil
            if import_log.present?
              import_log.update!(
                status: 'failed',
                completed_at: Time.current,
                error_messages: ["Scraper timed out after #{timeout} seconds. Last progress: #{last_scraped_count}/#{max_products} products scraped."].to_json
              )
            end
            return { success: false, error: "Scraper timed out after #{timeout} seconds" }
          end

          if IO.select([stdout, stderr], nil, nil, 1)
            begin
              if stdout.ready?
                chunk = stdout.read_nonblock(4096)
                output << chunk

                # Parse progress from output (looking for "[X/Y] Processing:" pattern)
                chunk.scan(/\[(\d+)\/(\d+)\] Processing:/) do |current, total|
                  scraped = current.to_i
                  if import_log.present? && scraped > last_scraped_count
                    last_scraped_count = scraped
                    last_progress_update = Time.now
                    import_log.update!(scraped_count: scraped)
                  end
                end
              end
            rescue EOFError, IO::WaitReadable
            end

            begin
              error_output << stderr.read_nonblock(4096) if stderr.ready?
            rescue EOFError, IO::WaitReadable
            end
          end

          # Check for stalled scraper (no progress for 5 minutes)
          if import_log.present? && (Time.now - last_progress_update) > 300
            Process.kill('TERM', wait_thr.pid) rescue nil
            import_log.update!(
              status: 'failed',
              completed_at: Time.current,
              error_messages: ["Scraper stalled - no progress for 5 minutes. Last progress: #{last_scraped_count}/#{max_products} products scraped."].to_json
            )
            return { success: false, error: "Scraper stalled - no progress for 5 minutes" }
          end
        end

        exit_status = wait_thr.value
        success = exit_status.success?
      end

      full_output = (output + error_output).join

      if success
        { success: true, output: full_output }
      else
        error_msg = 'Script execution failed'
        if import_log.present?
          import_log.update!(
            status: 'failed',
            completed_at: Time.current,
            error_messages: ["#{error_msg}. Scraped #{last_scraped_count}/#{max_products} products before failure."].to_json
          )
        end
        { success: false, error: error_msg, output: full_output }
      end

    rescue => e
      if import_log.present?
        import_log.update!(
          status: 'failed',
          completed_at: Time.current,
          error_messages: ["Scraper error: #{e.message}"].to_json
        )
      end
      { success: false, error: e.message, output: '' }
    end
  end

  def self.create_env_file(username:, password:, headless: true)
    env_content = <<~ENV
      INTERCARS_USERNAME=#{username}
      INTERCARS_PASSWORD=#{password}
      HEADLESS=#{headless}
      SLOW_MO=100
    ENV

    File.write(ENV_FILE, env_content)
  end

  def self.update_env(vars = {})
    if ENV_FILE.exist?
      content = File.read(ENV_FILE)
      vars.each do |key, value|
        if content.match?(/^#{key}=/)
          content.gsub!(/^#{key}=.*$/, "#{key}=#{value}")
        else
          content += "\n#{key}=#{value}"
        end
      end
      File.write(ENV_FILE, content)
    end
  end

  def self.latest_products_file
    Dir.glob(DATA_DIR.join('products-*.json'))
       .map { |f| Pathname.new(f) }
       .max_by(&:mtime)
  end

  def self.import_product(product_data, shop, import_log)
    # Create or update product using source_id from scraper (Inter Cars kod)
    source_id = product_data['source_id'] || product_data['sku'] || extract_source_id(product_data['source_url'])

    logger.info "Importing product: #{product_data['sku']} - #{product_data['title']}"

    product = shop.products.find_or_initialize_by(
      source: 'intercars',
      source_id: source_id
    )

    # Check if this is an update and if we should reuse existing data
    is_update = product.persisted?
    reuse_existing = product_data['reuse_existing'] == true

    if reuse_existing && is_update
      logger.info "  Action: FAST UPDATE (preserving images/tech description)"
    else
      logger.info "  Action: #{is_update ? 'UPDATE' : 'CREATE'}"
    end

    # Default price to 0 if not present
    price = product_data['price'] || 0.0

    # Build attributes - for reuse_existing, preserve certain fields
    attrs = {
      title: product_data['title'],
      sub_title: product_data['sub_title'],
      sku: product_data['sku'],
      brand: product_data['brand'],
      price: price,
      currency: product_data['currency'] || 'BAM',
      branch_availability: product_data['branch_availability'],
      quantity: product_data['quantity'],
      description: product_data['description'],
      specs: product_data['specs']&.to_json,
      import_source: 'intercars',
      refreshed_at: Time.current
    }

    # For reuse_existing mode, preserve technical_description, models, and images
    if reuse_existing && is_update
      # Don't overwrite these fields - keep existing values
      logger.info "  Preserving existing: technical_description, models, images"
    else
      # Full import - include technical description and models
      attrs[:technical_description] = product_data['technical_description']
      attrs[:models] = product_data['models']
      attrs[:image_urls] = product_data['images']
    end

    # Log what we're importing
    logger.info "  Sub-title: #{product_data['sub_title'] || 'MISSING'}"
    logger.info "  Brand: #{product_data['brand'] || 'MISSING'}"
    logger.info "  Price: #{price} #{product_data['currency'] || 'BAM'}"
    logger.info "  Images: #{reuse_existing ? 'PRESERVED' : (product_data['images']&.length || 0)}"
    logger.info "  Description: #{product_data['description'] ? 'YES' : 'NO'}"
    logger.info "  Technical Description: #{reuse_existing ? 'PRESERVED' : (product_data['technical_description'] ? 'YES' : 'NO')}"
    logger.info "  Models: #{reuse_existing ? 'PRESERVED' : (product_data['models'] || 'NONE')}"
    logger.info "  Specs: #{product_data['specs'] ? 'YES' : 'NO'}"

    # Assign OLX category template if import log has one
    if import_log&.olx_category_template_id.present?
      attrs[:olx_category_template_id] = import_log.olx_category_template_id
    end

    product.assign_attributes(attrs)
    product.save!

    # Download and attach images - skip for reuse_existing mode
    if reuse_existing && is_update
      logger.info "  ⚡ Skipping image download (reuse_existing mode)"
    elsif product_data['images'].present?
      logger.info "  Downloading #{product_data['images'].length} images..."
      product.images.purge if is_update && product.images.attached?
      download_images(product, product_data['images'])
    else
      logger.warn "  No images to download!"
    end

    # Update import log if provided
    if import_log.present?
      import_log.increment!(:successful_rows)
      import_log.increment!(:processed_rows)

      # Create ImportedProduct record for tracking
      ImportedProduct.create!(
        shop: shop,
        import_log: import_log,
        product: product,
        source: 'intercars',
        raw_data: product_data.to_json,
        status: 'imported'
      )
    end

    # Log final result
    if is_update
      logger.info "  ✓ Updated product #{product.sku}"
    else
      logger.info "  ✓ Created new product #{product.sku}"
    end

    product
  end

  def self.extract_source_id(url)
    # Extract ID from URL like: https://example.com/product/12345
    url.to_s.match(/\/(\d+)(?:\/|$)/)&.captures&.first || url
  end

  def self.download_images(product, image_urls)
    success_count = 0
    image_urls.each_with_index do |url, index|
      next if url.blank?

      begin
        # Try to download the best available quality image
        # Priority: use the provided size, or try larger sizes with fallback
        downloaded_url = download_best_available_image(url, product, index)

        if downloaded_url
          success_count += 1
          logger.debug "    ✓ Image #{index + 1}/#{image_urls.length} downloaded"
        else
          logger.error "    ✗ Failed to download image #{index + 1}: No valid size found"
        end
      rescue => e
        logger.error "    ✗ Failed to download image #{index + 1}: #{e.message}"
      end
    end
    logger.info "  ✓ Downloaded #{success_count}/#{image_urls.length} images"
  end

  ##
  # Try to download the best available image quality
  # Tries multiple sizes if the requested size fails (1200, 800, 600, 300)
  #
  # @param url [String] Original image URL
  # @param product [Product] Product to attach image to
  # @param index [Integer] Image index
  # @return [String, nil] Downloaded URL or nil if failed
  #
  def self.download_best_available_image(url, product, index)
    # If URL doesn't have a size transformation, try as-is first
    unless url.match?(/t_t\d+x\d+v\d+/)
      begin
        logger.debug "    Trying original URL (no transformation): #{url.truncate(80)}"
        io = URI.open(url)
        attach_image(product, io, url, index)
        return url
      rescue => e
        logger.debug "    Original URL failed: #{e.message}"
      end
    end

    # Try different sizes in order of preference: current size, 1200, 800, 600, 300
    sizes_to_try = []

    # Extract current size if present
    if url =~ /t_t(\d+)x(\d+)v\d+/
      current_width = $1.to_i
      current_height = $2.to_i

      # If current size is >= 300, try it first
      if current_width >= 300 && current_height >= 300
        sizes_to_try << { url: url, label: "#{current_width}x#{current_height} (original)" }
      end
    end

    # Add fallback sizes (only if not already in list)
    [
      { size: '1200x1200v1', label: '1200x1200' },
      { size: '800x800v1', label: '800x800' },
      { size: '600x600v1', label: '600x600' },
      { size: '300x300v2', label: '300x300' }
    ].each do |fallback|
      test_url = url.gsub(/t_t\d+x\d+v\d+/, "t_t#{fallback[:size]}")
      # Skip if we already have this URL in our list
      next if sizes_to_try.any? { |s| s[:url] == test_url }
      sizes_to_try << { url: test_url, label: fallback[:label] }
    end

    # Try each size until one succeeds
    sizes_to_try.each do |size_option|
      begin
        logger.debug "    Trying #{size_option[:label]}: #{size_option[:url].truncate(80)}"
        io = URI.open(size_option[:url])
        attach_image(product, io, size_option[:url], index)
        logger.debug "    ✓ Successfully downloaded #{size_option[:label]}"
        return size_option[:url]
      rescue OpenURI::HTTPError => e
        logger.debug "    #{size_option[:label]} not available (#{e.message})"
      rescue => e
        logger.debug "    #{size_option[:label]} failed: #{e.message}"
      end
    end

    nil
  end

  ##
  # Attach downloaded image to product
  #
  def self.attach_image(product, io, url, index)
    filename = "#{product.sku || product.id}_#{index}#{File.extname(url)}"
    product.images.attach(
      io: io,
      filename: filename,
      content_type: io.content_type
    )
  end
end
