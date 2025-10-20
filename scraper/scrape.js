/**
 * Main Scraping Script
 *
 * Scrapes product data from Intercars catalog
 * - Uses stealth mode to bypass Cloudflare
 * - Handles two-step SSO login
 * - Navigates product catalog with pagination
 * - Waits for React products to load
 * - Extracts product details including images
 * - Saves data to JSON
 */

const { chromium } = require('playwright-extra');
const stealth = require('puppeteer-extra-plugin-stealth');
const fs = require('fs');
require('dotenv').config();

// Add stealth plugin to avoid detection
chromium.use(stealth());

const SITE_URL = 'https://ba.e-cat.intercars.eu/bs/';
const PRODUCT_URL = process.env.PRODUCT_URL;
const MAX_PRODUCTS = parseInt(process.env.MAX_PRODUCTS) || 10;

async function scrapeProducts(username, password, productUrl) {
  console.log('🕷️  Starting Intercars Product Scraper (with Stealth Mode)...\n');

  // Use parameters if provided, otherwise fall back to env
  const loginUsername = username || process.env.INTERCARS_USERNAME;
  const loginPassword = password || process.env.INTERCARS_PASSWORD;
  const targetUrl = productUrl || PRODUCT_URL;

  if (!loginUsername || !loginPassword) {
    console.error('❌ Error: Credentials required');
    throw new Error('Missing credentials');
  }

  if (!targetUrl) {
    console.error('❌ Error: Product URL required');
    throw new Error('Missing product URL');
  }

  const browser = await chromium.launch({
    headless: process.env.HEADLESS === 'true',
    slowMo: parseInt(process.env.SLOW_MO) || 50,
    args: [
      '--disable-blink-features=AutomationControlled',
      '--no-sandbox',
      '--disable-setuid-sandbox'
    ]
  });

  const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    viewport: { width: 1920, height: 1080 },
    locale: 'en-US',
    timezoneId: 'America/New_York',
    permissions: ['geolocation']
  });

  const page = await context.newPage();

  // Enable console logging from page
  page.on('console', msg => console.log('   [Browser]:', msg.text()));

  const products = [];

  try {
    // Step 1: Login with two-step SSO
    console.log('🔐 Step 1: Logging in to Intercars...\n');

    await page.goto(SITE_URL, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(2000);

    console.log(`   Initial URL: ${page.url()}`);

    // Check if we're on SSO login page
    if (page.url().includes('account.intercars.eu') && page.url().includes('login')) {
      console.log('   Detected SSO login page - TWO-STEP LOGIN FLOW\n');

      // STEP 1: Enter email/username
      const emailField = page.locator('input#usernameUserInput').first();

      if (await emailField.count() > 0) {
        await emailField.fill(loginUsername);
        console.log(`   ✓ Email entered: ${loginUsername}`);

        // Submit email form
        const continueButton = page.locator('input[type="submit"]').first();
        if (await continueButton.count() > 0) {
          await continueButton.click();
          console.log('   ✓ Continue button clicked\n');

          await page.waitForTimeout(3000);
          await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});
        }
      }

      // STEP 2: Enter password
      const passwordField = page.locator('input[type="password"]').first();

      if (await passwordField.count() > 0) {
        await passwordField.fill(loginPassword);
        console.log('   ✓ Password entered');

        // Submit password form
        const signInButton = page.locator('button[type="submit"], input[type="submit"]').first();
        if (await signInButton.count() > 0) {
          await signInButton.click();
          console.log('   ✓ Sign in button clicked\n');

          await page.waitForTimeout(3000);
          await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});

          console.log(`   ✓ After login URL: ${page.url()}\n`);
        }
      } else {
        throw new Error('Password field not found - login failed');
      }
    }

    // Step 2: Navigate to product listing page
    console.log('📄 Step 2: Navigating to product listing page...\n');

    await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });

    // Wait for Cloudflare challenge to complete
    console.log('   Waiting for Cloudflare challenge to pass...');
    try {
      await page.waitForFunction(() => {
        return !document.title.includes('Just a moment');
      }, { timeout: 30000 });
      console.log('   ✓ Cloudflare challenge passed!');
    } catch (e) {
      console.log('   ⚠️  Still seeing "Just a moment..." - Cloudflare may be blocking us');
      console.log('   Waiting an additional 10 seconds...');
      await page.waitForTimeout(10000);
    }

    console.log(`   ✓ Product page loaded`);
    console.log(`   Product page URL: ${page.url()}\n`);

    // Step 3: Scrape products from all pages
    console.log(`🔬 Step 3: Scraping products with pagination (max ${MAX_PRODUCTS})...\n`);

    let currentPage = 0;
    let scrapedCount = 0;

    while (scrapedCount < MAX_PRODUCTS) {
      console.log(`\n   📖 Page ${currentPage + 1}`);

      // Wait for Cloudflare again (if needed)
      try {
        await page.waitForFunction(() => {
          return !document.title.includes('Just a moment');
        }, { timeout: 15000 });
      } catch (e) {
        // Continue if timeout
      }

      // Wait for React products to load - increased timeout for filtered pages
      console.log('   Waiting for React app to load products...');

      // Wait for network to settle first
      await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {
        console.log('   Network not idle, continuing anyway...');
      });

      // Give React time to render
      await page.waitForTimeout(8000);

      // Now check if we have products with actual titles (not just pagination)
      const hasRealProducts = await page.evaluate(() => {
        const links = document.querySelectorAll('[data-testid="productIndexLink"]');
        let realProductCount = 0;

        links.forEach(link => {
          const title = link.getAttribute('title') || link.textContent.trim();
          const url = link.href;

          // Real products have titles longer than 3 chars and don't end in /p/[number]
          if (title && title.length > 3 && !url.match(/\/p\/\d+$/)) {
            realProductCount++;
          }
        });

        console.log(`Found ${links.length} total links, ${realProductCount} real products`);
        return realProductCount > 0;
      });

      if (hasRealProducts) {
        console.log('   ✓ Real products found!');
      } else {
        console.log('   ⚠️  No real products found (only pagination). Page may be filtered to empty result.');
      }

      // Save the current listing page URL to return to later
      const listingPageUrl = page.url();
      console.log(`   📍 Listing page URL: ${listingPageUrl}`);

      // Extract product links from this page
      const productLinks = await extractProductLinksFromPage(page);

      if (productLinks.length === 0) {
        console.log('   ⚠️  No products found on this page.');
        console.log('   Taking screenshot for debugging...');

        // Ensure directories exist
        if (!fs.existsSync('screenshots')) fs.mkdirSync('screenshots', { recursive: true });
        if (!fs.existsSync('data')) fs.mkdirSync('data', { recursive: true });

        await page.screenshot({ path: `screenshots/debug-no-products-page-${currentPage}.png`, fullPage: true });

        // Try to save HTML for inspection
        const html = await page.content();
        fs.writeFileSync(`data/debug-page-${currentPage}.html`, html);
        console.log(`   Saved HTML to: data/debug-page-${currentPage}.html`);

        console.log('   Stopping pagination.');
        break;
      }

      // Visit each product detail page (respecting MAX_PRODUCTS limit)
      const remainingSlots = MAX_PRODUCTS - scrapedCount;
      const linksToVisit = productLinks.slice(0, remainingSlots);

      console.log(`   → Visiting ${linksToVisit.length} product detail pages...`);

      for (let i = 0; i < linksToVisit.length; i++) {
        const productLink = linksToVisit[i];
        console.log(`      [${scrapedCount + i + 1}/${MAX_PRODUCTS}] Fetching: ${productLink.title}`);

        try {
          const productDetails = await extractProductDetails(page, productLink);
          if (productDetails) {
            products.push(productDetails);
            scrapedCount++;
          }
        } catch (error) {
          console.log(`      ⚠️  Failed to extract: ${error.message}`);
        }

        // Respectful throttling between product pages
        if (i < linksToVisit.length - 1) {
          await page.waitForTimeout(1000);
        }
      }

      console.log(`   ✓ Scraped ${linksToVisit.length} products from this page (Total: ${scrapedCount}/${MAX_PRODUCTS})`);

      // If we've reached our limit, stop
      if (scrapedCount >= MAX_PRODUCTS) {
        console.log('   ✓ Reached maximum product limit');
        break;
      }

      // Navigate back to the listing page before clicking next
      console.log(`   ← Returning to listing page...`);
      await page.goto(listingPageUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
      await page.waitForTimeout(2000);

      // Check if there's a next page
      const nextButton = page.locator('[data-testid="pagination__next"]');
      const hasNextPage = await nextButton.count() > 0;

      if (!hasNextPage) {
        console.log('   ⚠️  No next button found - last page reached');
        break;
      }

      // If this page had fewer products than expected, might be last page
      if (productLinks.length < 8) {
        console.log('   ⚠️  Fewer products than expected on this page.');
        // Still try to go to next page in case there are more
      }

      // Click next button to go to next page
      try {
        await nextButton.click();
        console.log('   ✓ Clicked next page button');
        await page.waitForTimeout(2000);
        currentPage++;
      } catch (e) {
        console.log('   ⚠️  Failed to navigate to next page:', e.message);
        break;
      }
    }

    // Step 4: Save results
    console.log(`\n💾 Step 4: Saving results...`);

    // Ensure data directory exists
    const dataDir = 'data';
    if (!fs.existsSync(dataDir)) {
      fs.mkdirSync(dataDir, { recursive: true });
    }

    const outputFile = `${dataDir}/products-${Date.now()}.json`;
    fs.writeFileSync(outputFile, JSON.stringify(products, null, 2));

    console.log(`   ✓ Saved ${products.length} products to: ${outputFile}`);
    console.log(`\n📊 Summary:`);
    console.log(`   Total products scraped: ${products.length}`);
    if (products.length > 0) {
      console.log(`   Average fields per product: ${Math.round(
        products.reduce((sum, p) => sum + Object.keys(p).length, 0) / products.length
      )}`);
      console.log(`   Products with images: ${products.filter(p => p.images && p.images.length > 0).length}`);
    }

    return products;

  } catch (error) {
    console.error('\n❌ Error during scraping:', error.message);
    console.error(error.stack);
    if (!fs.existsSync('screenshots')) fs.mkdirSync('screenshots', { recursive: true });
    await page.screenshot({ path: 'screenshots/error-scrape.png' }).catch(() => {});
    throw error;
  } finally {
    await browser.close();
    console.log('\n✅ Scraping complete!\n');
  }
}

async function extractProductLinksFromPage(page) {
  // Extract product links AND prices from the listing page
  const links = await page.evaluate(() => {
    const productLinks = document.querySelectorAll('[data-testid="productIndexLink"]');
    const priceElements = document.querySelectorAll('[data-testid="wholesalePrice-new"], [data-test="wholesalePrice-new"]');

    console.log(`Found ${productLinks.length} product links and ${priceElements.length} price elements`);

    const extracted = [];
    productLinks.forEach((link, index) => {
      const title = link.getAttribute('title') || link.textContent.trim();
      const url = link.href;
      const sku = link.getAttribute('data-towkod');

      // Skip pagination links - they end with /c/[category]/p/[number]
      if (url.match(/\/p\/\d+$/)) {
        console.log(`Skipping pagination link: ${url}`);
        return;
      }

      // Skip if no real title (pagination links have empty or numeric titles)
      if (!title || title.length < 3) {
        console.log(`Skipping link with no/short title: "${title}" - ${url}`);
        return;
      }

      let price = null;
      let currency = 'BAM';
      let branchAvailability = null;
      let quantity = null;

      // Assume prices and links are in same order (most common pattern in listing pages)
      const priceEl = priceElements[index];
      if (priceEl) {
        console.log(`Matching price element ${index} for SKU ${sku}`);

        // Try data attribute first
        const dataPrice = priceEl.getAttribute('data-clk-listing-item-wholesale-price');
        if (dataPrice) {
          price = parseFloat(dataPrice);
          console.log(`  Price from data attribute: ${price}`);
        } else {
          // Fall back to parsing text content
          const priceText = priceEl.textContent.trim();
          console.log(`  Price text: "${priceText}"`);
          const priceMatch = priceText.match(/([\d\s,.]+)\s*(BAM|EUR|KM)?/);
          if (priceMatch) {
            const cleanPrice = priceMatch[1].replace(/\s/g, '').replace(',', '.');
            price = parseFloat(cleanPrice);
            currency = priceMatch[2] || 'BAM';
            console.log(`  Price from text: ${price} ${currency}`);
          }
        }
      } else {
        console.log(`No price element at index ${index} for SKU ${sku}`);
      }

      // Extract branch availability and quantity
      // Find parent container of the product link
      let parent = link;
      for (let i = 0; i < 10; i++) {
        parent = parent.parentElement;
        if (!parent) break;

        // Look for stock name (branch)
        const stockNameEl = parent.querySelector('[data-testid="stockName"], [data-test="stockName"]');
        if (stockNameEl) {
          branchAvailability = stockNameEl.getAttribute('data-clk-listing-item-availability-branch') || stockNameEl.textContent.trim();
          console.log(`  Found branch: ${branchAvailability}`);
        }

        // Look for stock quantity
        const stockQuantityEl = parent.querySelector('[data-testid="stockQuantity-new"], [data-test="stockQuantity-new"]');
        if (stockQuantityEl) {
          quantity = stockQuantityEl.getAttribute('data-clk-listing-item-availability-amount') || stockQuantityEl.textContent.trim();
          console.log(`  Found quantity: ${quantity}`);
        }

        // If we found both, no need to keep looking
        if (branchAvailability && quantity) {
          break;
        }
      }

      if (url && (title || sku)) {
        extracted.push({ title, url, sku, price, currency, branchAvailability, quantity });
      }
    });

    return extracted;
  });

  return links;
}

async function extractProductDetails(page, productLink) {
  // Visit product detail page and extract full information
  await page.goto(productLink.url, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(2000);

  // Extract product details from the detail page
  const details = await page.evaluate(() => {
    const product = {};

    // Try to find price - use data attribute first, then text content
    console.log('Looking for price element...');

    const priceEl = document.querySelector('[data-testid="wholesalePrice-new"], [data-test="wholesalePrice-new"]');

    if (priceEl) {
      console.log('Price element found!');

      // Try to get price from data attribute first (most reliable)
      const dataPrice = priceEl.getAttribute('data-clk-listing-item-wholesale-price');
      if (dataPrice) {
        product.price = parseFloat(dataPrice);
        product.currency = 'BAM'; // Default currency
        console.log(`Found price from data attribute: ${product.price}`);
      } else {
        // Fall back to parsing text content
        const priceText = priceEl.textContent.trim();
        console.log(`Price element text: "${priceText}"`);

        // Match price in format "84,31 BAM" or "84.31 EUR"
        const priceMatch = priceText.match(/([\d\s,.]+)\s*(BAM|EUR|KM)?/);
        if (priceMatch) {
          const cleanPrice = priceMatch[1].replace(/\s/g, '').replace(',', '.');
          product.price = parseFloat(cleanPrice);
          product.currency = priceMatch[2] || (priceText.includes('€') ? 'EUR' : 'BAM');
          console.log(`Found price from text: ${product.price} ${product.currency}`);
        } else {
          console.log('No price match found in text');
        }
      }
    } else {
      console.log('Price element not found - trying alternative selectors...');

      // Try broader selectors as fallback
      const altSelectors = [
        '[class*="price"]',
        '[data-testid*="price"]',
        '.product-price',
        '[class*="Price"]'
      ];

      for (const selector of altSelectors) {
        const altPriceEl = document.querySelector(selector);
        if (altPriceEl) {
          const priceText = altPriceEl.textContent.trim();
          const priceMatch = priceText.match(/([\d\s,.]+)\s*(BAM|EUR|KM)?/);
          if (priceMatch) {
            const cleanPrice = priceMatch[1].replace(/\s/g, '').replace(',', '.');
            product.price = parseFloat(cleanPrice);
            product.currency = priceMatch[2] || 'BAM';
            console.log(`Found price with fallback selector ${selector}: ${product.price} ${product.currency}`);
            break;
          }
        }
      }
    }

    // Extract images
    const images = [];
    document.querySelectorAll('img').forEach(img => {
      let src = img.src || img.getAttribute('data-src');
      if (src && src.includes('ic-files-res.cloudinary.com')) {
        // Get high-res version
        src = src.replace(/w_\d+/, 'w_800').replace(/h_\d+/, 'h_800');
        if (!images.includes(src)) {
          images.push(src);
        }
      }
    });
    product.images = images;

    // Extract specifications/attributes
    const specs = {};
    const specRows = document.querySelectorAll('[class*="spec"], [class*="attribute"], tr');

    specRows.forEach(row => {
      const label = row.querySelector('th, td:first-child, [class*="label"]');
      const value = row.querySelector('td:last-child, [class*="value"]');

      if (label && value) {
        const labelText = label.textContent.trim();
        const valueText = value.textContent.trim();
        if (labelText && valueText) {
          specs[labelText] = valueText;
        }
      }
    });

    if (Object.keys(specs).length > 0) {
      product.specs = specs;

      // Build description from specs
      const descParts = [];
      for (const [key, value] of Object.entries(specs)) {
        descParts.push(`${key}: ${value}`);
      }
      product.description = descParts.join('\n');

      // Extract brand from specs (look for "Brend:" or "Brand:")
      for (const [key, value] of Object.entries(specs)) {
        if (key.toLowerCase().includes('brend') || key.toLowerCase().includes('brand')) {
          product.brand = value;
          console.log(`Found brand in specs: ${value}`);
          break;
        }
      }
    }

    // If brand not found in specs, try DOM selectors
    if (!product.brand) {
      const brandSelectors = [
        '[class*="brand"]',
        '[data-testid*="brand"]',
        '.manufacturer'
      ];

      for (const selector of brandSelectors) {
        const brandEl = document.querySelector(selector);
        if (brandEl) {
          product.brand = brandEl.textContent.trim();
          console.log(`Found brand in DOM: ${product.brand}`);
          break;
        }
      }
    }

    return product;
  });

  // Combine with link data (use price from listing page as it's more reliable)
  return {
    source: 'intercars',
    scraped_at: new Date().toISOString(),
    title: productLink.title,
    sku: productLink.sku,
    source_id: productLink.sku,
    source_url: productLink.url,
    price: productLink.price || details.price || 0.0,
    currency: productLink.currency || details.currency || 'BAM',
    branch_availability: productLink.branchAvailability || null,
    quantity: productLink.quantity || null,
    images: details.images || [],
    description: details.description || null,
    specs: details.specs ? JSON.stringify(details.specs) : null,
    brand: details.brand || null
  };
}

// Module export for use in Rails ScraperService
if (typeof module !== 'undefined' && module.exports) {
  module.exports = scrapeProducts;
}

// If run directly from command line
if (require.main === module) {
  scrapeProducts().catch(console.error);
}
