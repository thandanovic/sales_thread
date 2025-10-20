# Intercars Scraper - Playwright Scripts

This directory contains Playwright scripts for investigating and scraping product data from the Intercars e-catalog.

## Setup

### 1. Install Dependencies

```bash
cd scraper
npm install
```

This will install Playwright and its browsers.

### 2. Configure Credentials

```bash
cp .env.example .env
```

Edit `.env` and add your Intercars credentials:

```env
INTERCARS_USERNAME=your_email@example.com
INTERCARS_PASSWORD=your_password
HEADLESS=false
SLOW_MO=100
```

## Scripts

### 🔍 Investigate Script (`investigate.js`)

Explores the Intercars site to understand its structure without logging in.

```bash
npm run investigate
```

**What it does:**
- Loads the main page
- Detects if it's a login page or catalog
- Analyzes form elements and selectors
- Takes screenshots
- Saves page structure info

**Output:**
- `screenshots/01-initial-page.png` - Screenshot of initial page
- Console output with detected selectors

### 🔐 Login Test Script (`test-login.js`)

Tests the login flow with your credentials.

```bash
npm run test-login
```

**What it does:**
- Navigates to the site
- Detects login form fields automatically
- Fills in credentials from `.env`
- Submits the form
- Checks for success/errors
- Saves session cookies for reuse

**Output:**
- `screenshots/02-before-login.png` - Before login
- `screenshots/03-credentials-filled.png` - Form filled
- `screenshots/04-after-login.png` - After login (if successful)
- `data/session-cookies.json` - Saved session cookies
- `data/login-page.html` - Page HTML (if form not found)

**Run this first before scraping!**

### 🕷️ Scrape Script (`scrape.js`)

Scrapes product data from the catalog.

```bash
npm run scrape
```

**What it does:**
- Uses saved cookies from login test
- Navigates the product catalog
- Finds product links automatically
- Scrapes each product's details
- Saves data to JSON

**Output:**
- `data/products-[timestamp].json` - Scraped product data
- `screenshots/product-1.png` - First product screenshots
- `screenshots/05-catalog-page.png` - Catalog page (if no products found)

**Environment Variables:**
- `MAX_PRODUCTS=10` - Limit number of products to scrape
- `HEADLESS=false` - Show browser window (true to hide)
- `SLOW_MO=100` - Slow down actions (milliseconds)

## Usage Workflow

### First Time Setup:

```bash
# 1. Install
cd scraper
npm install

# 2. Configure
cp .env.example .env
# Edit .env with your credentials

# 3. Investigate the site
npm run investigate

# 4. Test login
npm run test-login

# 5. Scrape products
npm run scrape
```

### Subsequent Runs:

If cookies are still valid:
```bash
npm run scrape
```

If session expired:
```bash
npm run test-login
npm run scrape
```

## Integration with Rails

The scraped data is saved as JSON files that can be imported into Rails.

### Manual Import

```ruby
# In Rails console
json_data = JSON.parse(File.read('scraper/data/products-[timestamp].json'))

json_data.each do |product_data|
  Product.create!(
    title: product_data['title'],
    sku: product_data['sku'],
    brand: product_data['brand'],
    price: product_data['price'],
    currency: product_data['currency'],
    description: product_data['description'],
    specs: product_data['specs'],
    source: 'intercars'
  )
end
```

### Automated Import (TODO)

A Ruby service will be created to:
1. Call Playwright scripts via shell
2. Parse JSON output
3. Import products automatically

## Troubleshooting

### "Cannot find login form"

The site structure may have changed. Check:
1. `data/login-page.html` - Inspect the HTML
2. Update selectors in `test-login.js` if needed
3. Run `npm run investigate` to see current structure

### "No product links found"

The catalog page structure is different. Check:
1. `data/catalog-page.html` - Inspect the HTML
2. `screenshots/05-catalog-page.png` - Visual inspection
3. Update selectors in `scrape.js` if needed

### Login fails

- Check credentials in `.env`
- Site may have CAPTCHA (handle manually in browser)
- Try setting `HEADLESS=false` to see what happens
- Check for 2FA requirements

### Session expires

Sessions may expire after some time. Just run:
```bash
npm run test-login
```

## Data Format

Scraped products are saved as JSON:

```json
[
  {
    "source": "intercars",
    "source_url": "https://...",
    "scraped_at": "2024-01-15T10:30:00.000Z",
    "title": "Product Title",
    "sku": "PART-123",
    "brand": "Brand Name",
    "price": 85.50,
    "currency": "BAM",
    "description": "Product description...",
    "images": [
      "https://example.com/image1.jpg",
      "https://example.com/image2.jpg"
    ],
    "specs": {
      "Weight": "1.2kg",
      "Compatibility": "VW Golf VII",
      "Fitting Position": "Front Axle"
    }
  }
]
```

## Development Tips

### Run with visible browser

```bash
HEADLESS=false npm run scrape
```

### Slow down for debugging

```bash
SLOW_MO=500 npm run scrape
```

### Scrape fewer products

```bash
MAX_PRODUCTS=3 npm run scrape
```

### Combine settings

```bash
HEADLESS=false SLOW_MO=500 MAX_PRODUCTS=5 npm run scrape
```

## Files Structure

```
scraper/
├── investigate.js       # Site structure investigation
├── test-login.js        # Login flow testing
├── scrape.js            # Main scraping script
├── package.json         # Dependencies
├── .env                 # Your credentials (git-ignored)
├── .env.example         # Example config
├── README.md            # This file
├── screenshots/         # Browser screenshots
│   ├── 01-initial-page.png
│   ├── 02-before-login.png
│   ├── 03-credentials-filled.png
│   ├── 04-after-login.png
│   └── product-*.png
└── data/                # Output data
    ├── session-cookies.json
    ├── products-*.json
    ├── login-page.html
    └── catalog-page.html
```

## Next Steps

1. Run investigation to understand site structure
2. Test login with your credentials
3. Scrape a few products (set MAX_PRODUCTS=5)
4. Inspect the JSON output
5. Integrate with Rails import system
