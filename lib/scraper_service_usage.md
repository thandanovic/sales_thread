# ScraperService Usage Guide

The `ScraperService` provides a Ruby interface to the Playwright scraper scripts, allowing seamless integration with Rails.

## Setup

### 1. Install Scraper Dependencies

```bash
cd scraper
npm install
cd ..
```

### 2. Ensure Rails Can Find the Service

The service is in `lib/scraper_service.rb`. Make sure `lib/` is autoloaded in `config/application.rb`:

```ruby
# config/application.rb
config.autoload_paths << Rails.root.join('lib')
```

## Usage Examples

### In Rails Console

```ruby
# 1. Test login (first time)
result = ScraperService.test_login(
  username: 'your_email@example.com',
  password: 'your_password',
  headless: false  # Set true to hide browser
)

if result[:success]
  puts "Login successful!"
else
  puts "Login failed: #{result[:message]}"
end

# 2. Check if session is still valid
ScraperService.session_valid?
# => true

# 3. Scrape products
result = ScraperService.scrape_products(
  max_products: 10,
  headless: true
)

if result[:success]
  puts "Scraped #{result[:count]} products"
  puts "Data saved to: #{result[:file]}"
  pp result[:products].first
else
  puts "Scraping failed: #{result[:message]}"
end

# 4. Import scraped products to a shop
shop = Shop.first
result = ScraperService.import_from_json(
  'scraper/data/products-1234567890.json',
  shop
)

puts "Imported #{result[:imported]} of #{result[:total]} products"
result[:errors].each { |err| puts "Error: #{err}" }

# 5. Scrape AND import in one step
result = ScraperService.scrape_and_import(
  shop,
  max_products: 20
)

puts "Scraped: #{result[:scraped]}, Imported: #{result[:imported]}"
```

### In a Controller

```ruby
class ImportsController < ApplicationController
  def create_scrape
    shop = current_user.shops.find(params[:shop_id])

    # Test login first if needed
    unless ScraperService.session_valid?
      result = ScraperService.test_login(
        username: params[:username],
        password: params[:password],
        headless: true
      )

      unless result[:success]
        render json: { error: 'Login failed' }, status: :unauthorized
        return
      end
    end

    # Scrape and import
    result = ScraperService.scrape_and_import(
      shop,
      max_products: params[:max_products] || 10
    )

    if result[:success]
      render json: {
        message: "Successfully imported #{result[:imported]} products",
        scraped: result[:scraped],
        imported: result[:imported],
        errors: result[:errors]
      }
    else
      render json: { error: result[:message] }, status: :unprocessable_entity
    end
  end
end
```

### In a Rake Task

```ruby
# lib/tasks/scraper.rake
namespace :scraper do
  desc "Test Intercars login"
  task :test_login, [:username, :password] => :environment do |t, args|
    result = ScraperService.test_login(
      username: args[:username],
      password: args[:password],
      headless: ENV['HEADLESS'] != 'false'
    )

    if result[:success]
      puts "✅ Login successful!"
    else
      puts "❌ Login failed: #{result[:message]}"
    end
  end

  desc "Scrape products from Intercars"
  task :scrape, [:max_products] => :environment do |t, args|
    max = (args[:max_products] || 10).to_i

    result = ScraperService.scrape_products(max_products: max)

    if result[:success]
      puts "✅ Scraped #{result[:count]} products"
      puts "📁 Data saved to: #{result[:file]}"
    else
      puts "❌ Scraping failed: #{result[:message]}"
    end
  end

  desc "Import products to a shop"
  task :import, [:shop_id, :json_file] => :environment do |t, args|
    shop = Shop.find(args[:shop_id])

    result = ScraperService.import_from_json(args[:json_file], shop)

    puts "✅ Imported #{result[:imported]} of #{result[:total]} products"
    result[:errors].each { |err| puts "⚠️  #{err}" }
  end

  desc "Full scrape and import"
  task :full, [:shop_id, :max_products] => :environment do |t, args|
    shop = Shop.find(args[:shop_id])
    max = (args[:max_products] || 10).to_i

    result = ScraperService.scrape_and_import(shop, max_products: max)

    if result[:success]
      puts "✅ Scraped: #{result[:scraped]}, Imported: #{result[:imported]}"
      result[:errors].each { |err| puts "⚠️  #{err}" }
    else
      puts "❌ Failed: #{result[:message]}"
    end
  end
end
```

Then run:

```bash
# Test login
rails scraper:test_login[user@example.com,password]

# Scrape products
rails scraper:scrape[20]

# Import from JSON
rails scraper:import[1,scraper/data/products-123.json]

# Full scrape and import
rails scraper:full[1,50]
```

## API Methods

### `test_login(username:, password:, headless: true)`

Tests login and saves session cookies.

**Returns:**
```ruby
{ success: true, message: 'Login successful, session saved' }
# or
{ success: false, message: 'Login failed - ...', output: '...' }
```

### `scrape_products(max_products: 10, headless: true)`

Scrapes products using saved session.

**Returns:**
```ruby
{
  success: true,
  products: [...],      # Array of product hashes
  file: 'scraper/data/products-123.json',
  count: 10
}
# or
{ success: false, message: '...', output: '...' }
```

### `import_from_json(file_path, shop, import_log: nil)`

Imports products from JSON file into database.

**Returns:**
```ruby
{
  success: true,
  imported: 10,
  total: 10,
  errors: []
}
```

### `scrape_and_import(shop, max_products: 10, import_log: nil)`

Scrapes and imports in one step.

**Returns:**
```ruby
{
  success: true,
  scraped: 10,
  imported: 10,
  errors: [],
  file: 'scraper/data/products-123.json'
}
```

### `investigate`

Runs investigation script to analyze site structure.

**Returns:**
```ruby
{ success: true, output: '...' }
```

### `session_valid?`

Checks if there's a valid session (cookies < 24 hours old).

**Returns:** `true` or `false`

### `setup?`

Checks if scraper is properly set up.

**Returns:** `true` or `false`

## Error Handling

The service raises these exceptions:

- `ScraperService::ScraperError` - General scraper error
- `ScraperService::LoginError` - Login-specific error
- `ScraperService::ScrapeError` - Scraping-specific error

Wrap calls in begin/rescue:

```ruby
begin
  result = ScraperService.scrape_products(max_products: 50)
rescue ScraperService::ScraperError => e
  Rails.logger.error "Scraper error: #{e.message}"
end
```

## Troubleshooting

### "Scraper directory not found"

Make sure the `scraper/` directory exists with all scripts.

### "Node modules not installed"

Run:
```bash
cd scraper && npm install
```

### "No valid session found"

Run:
```ruby
ScraperService.test_login(username: '...', password: '...')
```

### Timeout errors

Increase timeout for large scrapes:
```ruby
# In scraper_service.rb, modify execute_script call
execute_script('scrape', timeout: 300)  # 5 minutes
```

## Integration with Import System

To integrate with your existing import system:

```ruby
# In your imports controller
def create_scrape
  shop = current_user.shops.find(params[:shop_id])

  # Create import log
  import_log = shop.import_logs.create!(
    source: 'intercars',
    status: 'pending'
  )

  begin
    # Scrape and import
    result = ScraperService.scrape_and_import(
      shop,
      max_products: params[:max_products],
      import_log: import_log
    )

    if result[:success]
      import_log.update!(
        status: 'completed',
        total_rows: result[:scraped],
        successful_rows: result[:imported],
        failed_rows: result[:errors].length
      )
    else
      import_log.update!(status: 'failed')
    end

  rescue => e
    import_log.update!(status: 'failed')
    raise
  end
end
```

## Background Job Integration (Future)

For async processing, wrap in a job:

```ruby
class ScraperImportJob < ApplicationJob
  queue_as :default

  def perform(shop_id, username, password, max_products)
    shop = Shop.find(shop_id)

    # Login
    login_result = ScraperService.test_login(
      username: username,
      password: password,
      headless: true
    )

    raise "Login failed" unless login_result[:success]

    # Scrape and import
    result = ScraperService.scrape_and_import(
      shop,
      max_products: max_products
    )

    # Notify user via email/notification
    # ...
  end
end
```

## Security Notes

- Never commit `.env` file with credentials
- Encrypt credentials in production
- Rate limit scraping requests
- Respect site's terms of service
- Handle CAPTCHA gracefully (pause, don't bypass)
