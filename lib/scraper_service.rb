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

    # Scrape with credentials
    scrape_result = scrape_products(
      max_products: max_products,
      username: username,
      password: password,
      product_url: product_url,
      headless: true
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

    # Import
    import_result = import_from_json(
      scrape_result[:file],
      shop,
      import_log: import_log
    )

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

    # Check if this is an update
    is_update = product.persisted?
    logger.info "  Action: #{is_update ? 'UPDATE' : 'CREATE'}"

    # Default price to 0 if not present
    price = product_data['price'] || 0.0

    attrs = {
      title: product_data['title'],
      sku: product_data['sku'],
      brand: product_data['brand'],
      price: price,
      currency: product_data['currency'] || 'BAM',
      branch_availability: product_data['branch_availability'],
      quantity: product_data['quantity'],
      description: product_data['description'],
      specs: product_data['specs']&.to_json,
      image_urls: product_data['images'],
      refreshed_at: Time.current
    }

    # Log what we're importing
    logger.info "  Brand: #{product_data['brand'] || 'MISSING'}"
    logger.info "  Price: #{price} #{product_data['currency'] || 'BAM'}"
    logger.info "  Images: #{product_data['images']&.length || 0}"
    logger.info "  Description: #{product_data['description'] ? 'YES' : 'NO'}"
    logger.info "  Specs: #{product_data['specs'] ? 'YES' : 'NO'}"

    # Assign OLX category template if import log has one
    if import_log&.olx_category_template_id.present?
      attrs[:olx_category_template_id] = import_log.olx_category_template_id
    end

    product.assign_attributes(attrs)
    product.save!

    # Download and attach images - clear old images first if updating
    if product_data['images'].present?
      logger.info "  Downloading #{product_data['images'].length} images..."
      product.images.purge if is_update && product.images.attached?
      download_images(product, product_data['images'])
    else
      logger.warn "  No images to download!"
    end

    # Update import log if provided
    import_log&.increment!(:successful_rows)

    # Create ImportedProduct record for tracking
    if import_log.present?
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
        # Convert thumbnail URLs to larger size (t_t100x100v2 -> t_t300x300v2)
        larger_url = url.gsub('t_t100x100v2', 't_t300x300v2')

        logger.debug "    Downloading: #{larger_url.truncate(80)}"

        io = URI.open(larger_url)
        filename = "#{product.sku || product.id}_#{index}#{File.extname(larger_url)}"

        product.images.attach(
          io: io,
          filename: filename,
          content_type: io.content_type
        )

        success_count += 1
        logger.debug "    ✓ Image #{index + 1}/#{image_urls.length} downloaded"
      rescue => e
        logger.error "    ✗ Failed to download image #{index + 1}: #{e.message}"
      end
    end
    logger.info "  ✓ Downloaded #{success_count}/#{image_urls.length} images"
  end
end
