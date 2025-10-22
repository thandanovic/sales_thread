# frozen_string_literal: true

namespace :scraper do
  desc 'Test scraper on a specific URL'
  task :test, [:url, :max_products] => :environment do |_t, args|
    if args[:url].blank?
      puts 'Error: Please provide a URL to scrape'
      puts 'Usage: rake scraper:test["https://ba.e-cat.intercars.eu/bs/path",10]'
      exit 1
    end

    url = args[:url]
    max_products = (args[:max_products] || 5).to_i

    puts '🕷️  Intercars Product Scraper - Test Mode'
    puts '=' * 80
    puts "URL: #{url}"
    puts "Max products: #{max_products}"
    puts '=' * 80

    # Get credentials from first shop with Intercars integration
    shop = Shop.first
    unless shop
      puts '✗ No shop found'
      exit 1
    end

    puts "Using shop: #{shop.name}"

    # Get Intercars credentials from ENV or prompt
    username = ENV['INTERCARS_USERNAME']
    password = ENV['INTERCARS_PASSWORD']

    if username.blank? || password.blank?
      puts "\n✗ Error: Intercars credentials not found"
      puts "Please set INTERCARS_USERNAME and INTERCARS_PASSWORD environment variables"
      puts "\nExample:"
      puts "  INTERCARS_USERNAME=your_email INTERCARS_PASSWORD=your_password rake scraper:test[\"#{url}\",#{max_products}]"
      exit 1
    end

    puts "Username: #{username}"
    puts '=' * 80
    puts ''

    begin
      # Run the scraper
      result = ScraperService.scrape_products(
        max_products: max_products,
        username: username,
        password: password,
        product_url: url,
        headless: true
      )

      if result[:success]
        puts "\n✓ Scraping completed successfully!"
        puts '=' * 80
        puts "Products scraped: #{result[:count]}"
        puts "JSON file: #{result[:file]}"

        # Show extraction stats
        products = result[:products]
        with_images = products.count { |p| p['images']&.any? }
        with_specs = products.count { |p| p['specs'].present? }
        with_brand = products.count { |p| p['brand'].present? }
        with_description = products.count { |p| p['description'].present? }

        puts "\nExtraction Statistics:"
        puts "  Products with images: #{with_images}/#{products.length} (#{(with_images.to_f / products.length * 100).round(1)}%)"
        puts "  Products with specs: #{with_specs}/#{products.length} (#{(with_specs.to_f / products.length * 100).round(1)}%)"
        puts "  Products with brand: #{with_brand}/#{products.length} (#{(with_brand.to_f / products.length * 100).round(1)}%)"
        puts "  Products with description: #{with_description}/#{products.length} (#{(with_description.to_f / products.length * 100).round(1)}%)"

        # Show first product details
        if products.any?
          puts "\nFirst Product Sample:"
          puts "  SKU: #{products[0]['sku']}"
          puts "  Title: #{products[0]['title']}"
          puts "  Brand: #{products[0]['brand'] || 'MISSING'}"
          puts "  Price: #{products[0]['price']} #{products[0]['currency']}"
          puts "  Images: #{products[0]['images']&.length || 0}"
          puts "  Has description: #{products[0]['description'].present? ? 'YES' : 'NO'}"
          puts "  Has specs: #{products[0]['specs'].present? ? 'YES' : 'NO'}"
        end

        # Show log files
        puts "\nLog Files:"

        # Find latest scraper log file
        scraper_logs = Dir.glob(File.join(ScraperService::SCRAPER_DIR, 'logs', 'scrape-*.log')).sort_by { |f| File.mtime(f) }.reverse
        if scraper_logs.any?
          puts "  Scraper log: #{scraper_logs.first}"
        end

        # Find latest Rails log file
        rails_logs = Dir.glob(File.join(ScraperService::LOG_DIR, 'scraper-*.log')).sort_by { |f| File.mtime(f) }.reverse
        if rails_logs.any?
          puts "  Rails log: #{rails_logs.first}"
        end

        puts "\n" + '=' * 80
        puts "✓ Test completed!"

      else
        puts "\n✗ Scraping failed!"
        puts "Error: #{result[:message]}"
        if result[:output].present?
          puts "\nOutput:"
          puts result[:output]
        end
        exit 1
      end

    rescue => e
      puts "\n✗ Test failed: #{e.message}"
      puts e.backtrace.first(10).join("\n") if ENV['DEBUG']
      exit 1
    end
  end

  desc 'Show scraper log files'
  task :logs => :environment do
    puts 'Scraper Log Files'
    puts '=' * 80

    # Scraper logs (Node.js)
    scraper_log_dir = File.join(ScraperService::SCRAPER_DIR, 'logs')
    if Dir.exist?(scraper_log_dir)
      scraper_logs = Dir.glob(File.join(scraper_log_dir, 'scrape-*.log')).sort_by { |f| File.mtime(f) }.reverse

      if scraper_logs.any?
        puts "\nNode.js Scraper Logs (#{scraper_log_dir}):"
        scraper_logs.first(5).each do |log_file|
          size = File.size(log_file) / 1024.0
          mtime = File.mtime(log_file)
          puts "  #{File.basename(log_file)} - #{size.round(1)} KB - #{mtime.strftime('%Y-%m-%d %H:%M:%S')}"
        end
      else
        puts "\nNo Node.js scraper logs found"
      end
    end

    # Rails logs
    if Dir.exist?(ScraperService::LOG_DIR)
      rails_logs = Dir.glob(File.join(ScraperService::LOG_DIR, 'scraper-*.log')).sort_by { |f| File.mtime(f) }.reverse

      if rails_logs.any?
        puts "\nRails Scraper Logs (#{ScraperService::LOG_DIR}):"
        rails_logs.each do |log_file|
          size = File.size(log_file) / 1024.0
          mtime = File.mtime(log_file)
          puts "  #{File.basename(log_file)} - #{size.round(1)} KB - #{mtime.strftime('%Y-%m-%d %H:%M:%S')}"
        end
      else
        puts "\nNo Rails scraper logs found"
      end
    end

    puts "\n" + '=' * 80
  end

  desc 'Clean old scraper log files (keeps last 7 days)'
  task :clean_logs => :environment do
    puts 'Cleaning old scraper log files...'
    puts '=' * 80

    deleted_count = 0
    cutoff_date = 7.days.ago

    # Clean Node.js logs
    scraper_log_dir = File.join(ScraperService::SCRAPER_DIR, 'logs')
    if Dir.exist?(scraper_log_dir)
      Dir.glob(File.join(scraper_log_dir, 'scrape-*.log')).each do |log_file|
        if File.mtime(log_file) < cutoff_date
          File.delete(log_file)
          deleted_count += 1
          puts "  Deleted: #{File.basename(log_file)}"
        end
      end
    end

    # Clean Rails logs
    if Dir.exist?(ScraperService::LOG_DIR)
      Dir.glob(File.join(ScraperService::LOG_DIR, 'scraper-*.log')).each do |log_file|
        if File.mtime(log_file) < cutoff_date
          File.delete(log_file)
          deleted_count += 1
          puts "  Deleted: #{File.basename(log_file)}"
        end
      end
    end

    puts "\n✓ Cleaned #{deleted_count} old log files"
    puts '=' * 80
  end
end
