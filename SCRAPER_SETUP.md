# Playwright Scraper Setup Guide

This guide will help you set up and use the Playwright scraper for the Intercars e-catalog.

## What's Been Created

```
olx_sale/
├── scraper/                        # Playwright scripts directory
│   ├── package.json                # Node dependencies
│   ├── investigate.js              # Site investigation script
│   ├── test-login.js               # Login testing script
│   ├── scrape.js                   # Main scraping script
│   ├── .env.example                # Example configuration
│   ├── .gitignore                  # Ignore sensitive files
│   ├── README.md                   # Detailed scraper docs
│   ├── screenshots/                # Browser screenshots (created on run)
│   └── data/                       # Output data (created on run)
├── lib/
│   ├── scraper_service.rb          # Rails integration service
│   └── scraper_service_usage.md    # Service usage examples
└── planing/
    └── init_plan.md                # Original technical plan
```

## Quick Start

### 1. Install Playwright

```bash
cd scraper
npm install
```

This installs Playwright and Chromium browser.

### 2. Configure Credentials

```bash
cp .env.example .env
```

Edit `.env`:
```env
INTERCARS_USERNAME=your_email@example.com
INTERCARS_PASSWORD=your_password
HEADLESS=false
SLOW_MO=100
```

### 3. Investigate the Site (Optional)

```bash
npm run investigate
```

This explores the site structure without logging in.

### 4. Test Login

```bash
npm run test-login
```

This will:
- Try to log in with your credentials
- Save session cookies if successful
- Take screenshots of the process
- Show you what happened

### 5. Scrape Products

```bash
npm run scrape
```

This will:
- Use saved session cookies
- Find product listings
- Scrape product details
- Save data to JSON

## Using from Rails

### Setup Rails Integration

In `config/application.rb`, ensure lib is autoloaded:

```ruby
config.autoload_paths << Rails.root.join('lib')
```

### Rails Console Example

```ruby
# 1. Test login
result = ScraperService.test_login(
  username: 'your@email.com',
  password: 'yourpassword'
)

# 2. Scrape products
result = ScraperService.scrape_products(max_products: 10)
puts "Scraped #{result[:count]} products"

# 3. Import to a shop
shop = Shop.first
result = ScraperService.import_from_json(
  result[:file],  # Use file from scrape
  shop
)
puts "Imported #{result[:imported]} products"

# OR do it all in one step:
result = ScraperService.scrape_and_import(shop, max_products: 20)
```

### Create a Rake Task

Create `lib/tasks/scraper.rake`:

```ruby
namespace :scraper do
  desc "Test login"
  task :login, [:username, :password] => :environment do |t, args|
    result = ScraperService.test_login(
      username: args[:username],
      password: args[:password]
    )
    puts result[:success] ? "✅ Success" : "❌ Failed: #{result[:message]}"
  end

  desc "Scrape products"
  task :scrape, [:max] => :environment do |t, args|
    result = ScraperService.scrape_products(max_products: args[:max].to_i || 10)
    puts "Scraped: #{result[:count]}" if result[:success]
  end

  desc "Full import to shop"
  task :import, [:shop_id, :max] => :environment do |t, args|
    shop = Shop.find(args[:shop_id])
    result = ScraperService.scrape_and_import(shop, max_products: args[:max].to_i || 10)
    puts "Imported: #{result[:imported]} of #{result[:scraped]}"
  end
end
```

Then run:

```bash
rails scraper:login[email@example.com,password]
rails scraper:scrape[20]
rails scraper:import[1,50]
```

## How It Works

### 1. Playwright Scripts (Node.js)

Three independent JavaScript scripts:

- **investigate.js** - Explores site structure, finds selectors
- **test-login.js** - Tests login, saves cookies
- **scrape.js** - Scrapes products using saved session

### 2. ScraperService (Ruby)

Ruby service that:
- Executes Playwright scripts via shell
- Parses JSON output
- Imports data into Rails models
- Handles errors gracefully

### 3. Data Flow

```
┌──────────────┐
│   Rails App  │
└──────┬───────┘
       │ ScraperService.scrape_products()
       ▼
┌──────────────┐
│  Shell Exec  │
└──────┬───────┘
       │ node scrape.js
       ▼
┌──────────────┐
│  Playwright  │  ←── Intercars Site
└──────┬───────┘
       │
       ▼
  products.json
       │
       ▼
┌──────────────┐
│ Import Logic │
└──────┬───────┘
       │
       ▼
  Product Model
```

## Troubleshooting

### Can't find login form

The site structure may have changed:

1. Run `npm run investigate` with `HEADLESS=false`
2. Check `data/login-page.html`
3. Update selectors in `test-login.js`

### Login fails

- Check credentials in `.env`
- Look for CAPTCHA (handle manually)
- Check screenshots in `screenshots/`
- Try `HEADLESS=false` to see what's happening

### No products found

- Check `data/catalog-page.html`
- Look at `screenshots/05-catalog-page.png`
- Update selectors in `scrape.js`

### Session expires

Sessions expire after ~24 hours. Just run:

```bash
npm run test-login
```

Or from Rails:

```ruby
ScraperService.test_login(username: '...', password: '...')
```

## Tips & Best Practices

### Development Mode

Run with visible browser:

```bash
HEADLESS=false npm run scrape
```

### Slow Down for Debugging

```bash
SLOW_MO=500 npm run scrape
```

### Scrape Fewer Products

```bash
MAX_PRODUCTS=5 npm run scrape
```

### Check Session Status

```ruby
ScraperService.session_valid?
```

### Re-investigate After Site Changes

```bash
npm run investigate
```

This helps you find new selectors.

## Next Steps

1. **Test the scraper**
   ```bash
   cd scraper
   npm install
   cp .env.example .env
   # Edit .env with credentials
   npm run investigate
   npm run test-login
   npm run scrape
   ```

2. **Test Rails integration**
   ```bash
   rails console
   > ScraperService.setup?
   > result = ScraperService.test_login(username: '...', password: '...')
   > result = ScraperService.scrape_products(max_products: 5)
   ```

3. **Integrate with your app**
   - Add controller endpoint
   - Create background job (optional)
   - Add UI for initiating scrapes
   - Handle import logs

## Security Checklist

- ✅ `.env` is in `.gitignore`
- ✅ Credentials never committed to git
- ✅ Session cookies stored temporarily
- ✅ Rate limiting (1s between requests)
- ✅ Respectful scraping (no bypassing CAPTCHA)
- ⚠️ Encrypt credentials in production
- ⚠️ Add rate limiting in controllers
- ⚠️ Monitor for site changes

## Files Reference

| File | Purpose |
|------|---------|
| `scraper/investigate.js` | Explore site structure |
| `scraper/test-login.js` | Test login flow |
| `scraper/scrape.js` | Main scraping logic |
| `scraper/README.md` | Detailed scraper docs |
| `lib/scraper_service.rb` | Rails integration |
| `lib/scraper_service_usage.md` | Service examples |
| `SCRAPER_SETUP.md` | This file |

## Support

If selectors break (site changes):

1. Run `npm run investigate`
2. Check `data/*.html` files
3. Update selectors in scripts
4. Test with `HEADLESS=false`
5. Document changes

The scraper is designed to be maintainable - all selectors are configurable and scripts are well-commented.
