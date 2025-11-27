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
const path = require('path');
require('dotenv').config();

// Add stealth plugin to avoid detection
chromium.use(stealth());

const SITE_URL = 'https://ba.e-cat.intercars.eu/bs/';
const PRODUCT_URL = process.env.PRODUCT_URL;
const MAX_PRODUCTS = parseInt(process.env.MAX_PRODUCTS) || 10;

// Setup logging to file
const LOG_DIR = path.join(__dirname, 'logs');
if (!fs.existsSync(LOG_DIR)) {
  fs.mkdirSync(LOG_DIR, { recursive: true });
}

const LOG_FILE = path.join(LOG_DIR, `scrape-${Date.now()}.log`);
const logStream = fs.createWriteStream(LOG_FILE, { flags: 'a' });

function log(message) {
  const timestamp = new Date().toISOString();
  const logMessage = `[${timestamp}] ${message}\n`;

  // Write to both console and file
  console.log(message);
  logStream.write(logMessage);
}

function logError(message, error) {
  const timestamp = new Date().toISOString();
  const logMessage = `[${timestamp}] ERROR: ${message}\n${error ? error.stack : ''}\n`;

  console.error(message, error);
  logStream.write(logMessage);
}

async function scrapeProducts(username, password, productUrl) {
  log('🕷️  Starting Intercars Product Scraper (with Stealth Mode)...');
  log(`Log file: ${LOG_FILE}`);

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

      // CRITICAL FIX: Scroll to bottom of page to trigger lazy-loaded price elements
      // Products below the fold don't have price elements rendered until scrolled into view
      console.log('   📜 Scrolling to bottom to load all price elements...');
      await page.evaluate(() => {
        window.scrollTo(0, document.body.scrollHeight);
      });
      await page.waitForTimeout(2000); // Wait for lazy-loaded elements to render

      // Scroll back to top for consistent extraction
      await page.evaluate(() => {
        window.scrollTo(0, 0);
      });
      await page.waitForTimeout(1000);
      console.log('   ✓ All products should now be fully loaded');

      // Extract products directly from listing page (no detail page visits)
      const productCards = await extractProductsFromListingPage(page);

      if (productCards.length === 0) {
        log('   ⚠️  No products found on this page.');
        log('   Taking screenshot for debugging...');

        // Ensure directories exist
        if (!fs.existsSync('screenshots')) fs.mkdirSync('screenshots', { recursive: true });
        if (!fs.existsSync('data')) fs.mkdirSync('data', { recursive: true });

        await page.screenshot({ path: `screenshots/debug-no-products-page-${currentPage}.png`, fullPage: true });

        // Try to save HTML for inspection
        const html = await page.content();
        fs.writeFileSync(`data/debug-page-${currentPage}.html`, html);
        log(`   Saved HTML to: data/debug-page-${currentPage}.html`);

        log('   Stopping pagination.');
        break;
      }

      // Process products on this page (respecting MAX_PRODUCTS limit)
      const remainingSlots = MAX_PRODUCTS - scrapedCount;
      const productsToProcess = productCards.slice(0, remainingSlots);

      log(`   → Processing ${productsToProcess.length} products on listing page...`);

      for (let i = 0; i < productsToProcess.length; i++) {
        const productData = productsToProcess[i];
        log(`      [${scrapedCount + i + 1}/${MAX_PRODUCTS}] Processing: ${productData.title}`);

        try {
          // Extract images using the imageContainerIndex stored during product extraction
          // This ensures we click on the exact same container that corresponds to this product
          const images = await extractImagesFromProductCard(page, productData.imageContainerIndex);
          productData.images = images;

          log(`       ✓ Extracted ${images.length} images without leaving listing page`);

          // Remove the temporary imageContainerIndex before saving
          delete productData.imageContainerIndex;

          products.push(productData);
          scrapedCount++;
        } catch (error) {
          logError(`Failed to extract images for product ${i}`, error);
          // Still add product without images
          productData.images = [];

          // Remove the temporary imageContainerIndex before saving
          delete productData.imageContainerIndex;

          products.push(productData);
          scrapedCount++;
        }

        // Small delay between products
        if (i < productsToProcess.length - 1) {
          await page.waitForTimeout(500);
        }
      }

      log(`   ✓ Scraped ${productsToProcess.length} products from this page (Total: ${scrapedCount}/${MAX_PRODUCTS})`);

      // If we've reached our limit, stop
      if (scrapedCount >= MAX_PRODUCTS) {
        log('   ✓ Reached maximum product limit');
        break;
      }

      // Check if there's a next page
      const nextButton = page.locator('[data-testid="pagination__next"]');
      const hasNextPage = await nextButton.count() > 0;

      if (!hasNextPage) {
        log('   ⚠️  No next button found - last page reached');
        break;
      }

      // If this page had fewer products than expected, might be last page
      if (productCards.length < 8) {
        log('   ⚠️  Fewer products than expected on this page.');
        // Still try to go to next page in case there are more
      }

      // Click next button to go to next page
      try {
        await nextButton.click();
        log('   ✓ Clicked next page button');
        await page.waitForTimeout(2000);
        currentPage++;
      } catch (e) {
        log('   ⚠️  Failed to navigate to next page: ' + e.message);
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
    logError('Error during scraping', error);
    if (!fs.existsSync('screenshots')) fs.mkdirSync('screenshots', { recursive: true });
    await page.screenshot({ path: 'screenshots/error-scrape.png' }).catch(() => {});
    throw error;
  } finally {
    await browser.close();
    log('\n✅ Scraping complete!');
    log(`Full log saved to: ${LOG_FILE}`);

    // Close log stream
    logStream.end();
  }
}

/**
 * Extract all product data from listing page (without visiting detail pages)
 * Also tracks which image container index corresponds to each product for accurate image extraction
 */
async function extractProductsFromListingPage(page) {
  log('   Extracting products from listing page...');

  const products = await page.evaluate(() => {
    const productLinks = document.querySelectorAll('[data-testid="productIndexLink"]');
    // Get ALL .product-image containers as an array for index lookup
    const allImageContainers = Array.from(document.querySelectorAll('.product-image'));

    console.log(`[EXTRACTION] Found ${productLinks.length} product links and ${allImageContainers.length} image containers`);

    const extracted = [];
    let realProductIndex = 0; // Track index of real products (excluding pagination)

    productLinks.forEach((link, linkIndex) => {
      const title = link.getAttribute('title') || link.textContent.trim();
      const url = link.href;
      const sku = link.getAttribute('data-towkod');

      // Skip pagination links - they end with /c/[category]/p/[number]
      if (url.match(/\/p\/\d+$/)) {
        console.log(`[EXTRACTION] Skipping pagination link: ${url}`);
        return;
      }

      // Skip if no real title (pagination links have empty or numeric titles)
      if (!title || title.length < 3) {
        console.log(`[EXTRACTION] Skipping link with no/short title: "${title}"`);
        return;
      }

      console.log(`[EXTRACTION] Processing product ${linkIndex} (real product index: ${realProductIndex}): ${title} (${sku})`);

      let price = null;
      let currency = 'BAM';
      let branchAvailability = null;
      let quantity = null;

      // CRITICAL FIX: Extract price by traversing DOM from the product link
      // This ensures we get the price for THIS specific product, not from a misaligned array
      let parent = link;
      for (let i = 0; i < 10; i++) {
        parent = parent.parentElement;
        if (!parent) break;

        // Look for price element within this product's parent container
        const priceEl = parent.querySelector('[data-testid="wholesalePrice-new"], [data-test="wholesalePrice-new"]');
        if (priceEl) {
          const dataPrice = priceEl.getAttribute('data-clk-listing-item-wholesale-price');
          if (dataPrice) {
            price = parseFloat(dataPrice);
            console.log(`[EXTRACTION] Found price from data attribute: ${price}`);
          } else {
            const priceText = priceEl.textContent.trim();
            const priceMatch = priceText.match(/([\d\s,.]+)\s*(BAM|EUR|KM)?/);
            if (priceMatch) {
              const cleanPrice = priceMatch[1].replace(/\s/g, '').replace(',', '.');
              price = parseFloat(cleanPrice);
              currency = priceMatch[2] || 'BAM';
              console.log(`[EXTRACTION] Found price from text: ${price} ${currency}`);
            }
          }
        }

        // Extract branch availability
        const stockNameEl = parent.querySelector('[data-testid="stockName"], [data-test="stockName"]');
        if (stockNameEl) {
          branchAvailability = stockNameEl.getAttribute('data-clk-listing-item-availability-branch') || stockNameEl.textContent.trim();
        }

        // Extract quantity
        const stockQuantityEl = parent.querySelector('[data-testid="stockQuantity-new"], [data-test="stockQuantity-new"]');
        if (stockQuantityEl) {
          quantity = stockQuantityEl.getAttribute('data-clk-listing-item-availability-amount') || stockQuantityEl.textContent.trim();
        }

        // Stop if we found all the data we need
        if (price && branchAvailability && quantity) break;
      }

      // Try to extract brand from title (format: "SIZE BRAND CODE")
      let brand = null;
      const titleParts = title.split(' ');
      if (titleParts.length >= 2) {
        // Second part is usually the brand (e.g., "175/65R14 ZOHA 82T W462H" -> ZOHA)
        brand = titleParts[1];
      }

      // Extract specs/description from productAttributes section
      let description = null;
      let specs = {};

      // Try to find productAttributes container for this product
      // Navigate up from the link to find the product card that contains attributes
      let productCard = link;
      for (let i = 0; i < 15; i++) {
        productCard = productCard.parentElement;
        if (!productCard) break;

        const attrsContainer = productCard.querySelector('[data-testid="productAttributes"]');
        if (attrsContainer) {
          console.log(`[EXTRACTION] Found productAttributes for product ${realProductIndex}`);

          // Get the full text content and split by | to get attribute pairs
          const fullText = attrsContainer.textContent.trim();
          console.log(`[EXTRACTION] Attrs text length: ${fullText.length}`);

          if (fullText.length > 0) {
            // Split by | separator
            const parts = fullText.split('|').map(p => p.trim()).filter(p => p.length > 0);
            console.log(`[EXTRACTION] Found ${parts.length} attribute parts`);

            // Process each part (format: "Label: Value")
            const descParts = [];
            parts.forEach(part => {
              const colonIdx = part.indexOf(':');
              if (colonIdx > 0) {
                const label = part.substring(0, colonIdx).trim();
                const value = part.substring(colonIdx + 1).trim();

                if (label && value) {
                  descParts.push(`${label}: ${value}`);
                  specs[label] = value;
                }
              }
            });

            description = descParts.join(', ');
            console.log(`[EXTRACTION] Extracted ${Object.keys(specs).length} spec attributes`);
          } else {
            console.log(`[EXTRACTION] ⚠ productAttributes container is empty`);
          }
          break;
        }
      }

      if (!description) {
        console.log(`[EXTRACTION] ⚠ No productAttributes found for product ${realProductIndex}`);
      }

      console.log(`[EXTRACTION] Product ${realProductIndex} fields:`);
      console.log(`[EXTRACTION]   - Title: ${title}`);
      console.log(`[EXTRACTION]   - SKU: ${sku}`);
      console.log(`[EXTRACTION]   - Brand: ${brand || 'NOT FOUND'}`);
      console.log(`[EXTRACTION]   - Price: ${price || 'NOT FOUND'} ${currency}`);
      console.log(`[EXTRACTION]   - Branch: ${branchAvailability || 'NOT FOUND'}`);
      console.log(`[EXTRACTION]   - Quantity: ${quantity || 'NOT FOUND'}`);
      console.log(`[EXTRACTION]   - Description: ${description ? 'YES (' + description.substring(0, 50) + '...)' : 'NOT FOUND'}`);
      console.log(`[EXTRACTION]   - Specs: ${Object.keys(specs).length} attributes`);

      if (url && (title || sku)) {
        // CRITICAL FIX: Find the actual .product-image container that belongs to THIS product
        // by traversing up from the link to find the parent product card
        let imageContainerIndex = -1;
        let parent = link;

        // Traverse up the DOM to find the product card container
        for (let i = 0; i < 15; i++) {
          parent = parent.parentElement;
          if (!parent) break;

          // Look for .product-image within this parent
          const imageContainer = parent.querySelector('.product-image');
          if (imageContainer) {
            // Find the index of this container in the global array
            imageContainerIndex = allImageContainers.indexOf(imageContainer);
            if (imageContainerIndex >= 0) {
              console.log(`[EXTRACTION] Found image container at global index ${imageContainerIndex} for product link ${linkIndex} (real product ${realProductIndex})`);
              break;
            }
          }
        }

        if (imageContainerIndex === -1) {
          console.log(`[EXTRACTION] ⚠ WARNING: Product ${realProductIndex} has NO image container (product without images)`);
          // DO NOT fallback to any index - this product genuinely has no images
          // The image extraction will handle this by returning empty array
          console.log(`[EXTRACTION] Will skip image extraction for this product to prevent mismatch`);
        }

        const productData = {
          source: 'intercars',
          scraped_at: new Date().toISOString(),
          title,
          url,
          sku,
          source_id: sku,
          source_url: url,
          price: price || 0.0,
          currency,
          branch_availability: branchAvailability || null,
          quantity: quantity || null,
          brand: brand || null,
          // Images will be filled by clicking
          images: [],
          // Description and specs extracted from productAttributes
          description: description,
          specs: Object.keys(specs).length > 0 ? specs : null,
          // IMPORTANT: Store the ACTUAL index of the image container in the global array
          // This ensures we click on the exact right container
          // -1 means this product has no image container (will skip image extraction)
          imageContainerIndex: imageContainerIndex
        };
        extracted.push(productData);
        console.log(`[EXTRACTION] ✓ Added product ${realProductIndex} (link ${linkIndex}, image container index: ${imageContainerIndex})`);

        // Increment the real product index for the next product
        realProductIndex++;
      } else {
        console.log(`[EXTRACTION] ⚠ Skipped product link ${linkIndex} - missing URL or title/SKU`);
      }
    });

    console.log(`[EXTRACTION] Total extracted: ${extracted.length} products`);
    return extracted;
  });

  log(`   ✓ Found ${products.length} products on listing page`);
  return products;
}

/**
 * Extract images by clicking on product image to open modal
 * Stays on listing page - no navigation needed
 *
 * @param page - Playwright page object
 * @param containerIndex - The exact DOM index of the image container (from productLinks iteration)
 */
async function extractImagesFromProductCard(page, containerIndex) {
  try {
    log(`       [IMG] ========================================`);
    log(`       [IMG] Extracting images using container index ${containerIndex}...`);

    // CRITICAL: If containerIndex is -1, this product has NO image container
    // This happens when products don't have images at all
    if (containerIndex === -1) {
      log(`       [IMG] ⚠ Container index is -1: This product has NO images (skipping extraction)`);
      log(`       [IMG] ========================================`);
      return [];
    }

    // CRITICAL: Ensure no modal is open before clicking on this product
    // This prevents images from previous modals being attached to wrong products
    log(`       [IMG] Ensuring no modal is currently open...`);

    // Check for any existing modal portal
    const existingModalCount = await page.locator('.ReactModalPortal').count();
    if (existingModalCount > 0) {
      log(`       [IMG] ⚠ Found existing modal portal, forcefully closing it...`);

      // Try to close it
      await page.keyboard.press('Escape');
      await page.waitForTimeout(1000);
      await page.keyboard.press('Escape');
      await page.waitForTimeout(1000);

      // Verify it's gone
      const stillExists = await page.locator('.ReactModalPortal').count();
      if (stillExists > 0) {
        log(`       [IMG] ⚠ Modal portal still exists after ESC! Trying harder...`);
        await page.mouse.click(10, 10); // Click outside
        await page.waitForTimeout(2000);

        const finalCheck = await page.locator('.ReactModalPortal').count();
        if (finalCheck > 0) {
          log(`       [IMG] ✗ ERROR: Cannot close existing modal! Skipping this product to avoid image mismatch.`);
          return [];
        }
      }

      log(`       [IMG] ✓ Existing modal closed successfully`);
    } else {
      log(`       [IMG] ✓ No existing modal found, safe to proceed`);
    }

    // Additional wait to ensure DOM is stable
    await page.waitForTimeout(1000);

    // Get all image containers in DOM order - MUST use same selector as product extraction
    // to ensure indices match perfectly
    log(`       [IMG] Looking for image containers...`);
    const allImageContainers = await page.locator('.product-image').all();
    log(`       [IMG] Found ${allImageContainers.length} total image containers on page`);

    // Use the EXACT index that was stored during product extraction
    // This ensures we're clicking on the image container that corresponds to the same DOM position
    if (containerIndex < 0 || containerIndex >= allImageContainers.length) {
      logError(`[IMG] ⚠ Container index ${containerIndex} is invalid (found ${allImageContainers.length} containers)`, null);
      log(`       [IMG] This product will have no images to prevent mismatch`);
      log(`       [IMG] ========================================`);
      return [];
    }

    const container = allImageContainers[containerIndex];
    log(`       [IMG] Using image container at DOM index ${containerIndex}`);

    // Check if this container has a real image or just an SVG placeholder
    // Products without images show an SVG placeholder (no-image icon)
    log(`       [IMG] Checking if container has real images or just SVG placeholder...`);
    const hasRealImage = await container.evaluate((el) => {
      // Check if there's an <img> element (real product image)
      const imgElement = el.querySelector('img');
      if (imgElement) {
        return true;
      }

      // If only SVG exists, it's a placeholder for "no image available"
      const svgElement = el.querySelector('svg');
      if (svgElement && !imgElement) {
        console.log('[IMG CHECK] Only SVG placeholder found, no real images');
        return false;
      }

      return false;
    });

    if (!hasRealImage) {
      log(`       [IMG] ⚠ Product has no images (SVG placeholder only), skipping image extraction`);
      return [];
    }

    log(`       [IMG] ✓ Container has real images, proceeding with extraction`);

    // Try to click on the product image to open modal
    log(`       [IMG] Looking for product image to click...`);

    try {
      const productImage = container.locator('img').first();
      const productImageCount = await productImage.count();
      log(`       [IMG] Found ${productImageCount} img elements in container`);

      if (productImageCount === 0) {
        log(`       [IMG] ⚠ No images found in container, skipping`);
        return [];
      }

      log(`       [IMG] Scrolling image into view...`);
      await productImage.scrollIntoViewIfNeeded();
      await page.waitForTimeout(500);

      log(`       [IMG] CLICKING on product image to open modal...`);
      await productImage.click();

      log(`       [IMG] Waiting 5 seconds for modal to appear...`);
      await page.waitForTimeout(5000);

      // CRITICAL: Verify that a modal actually appeared after clicking
      const modalAppearedCount = await page.locator('.ReactModalPortal').count();
      if (modalAppearedCount === 0) {
        log(`       [IMG] ⚠ No modal appeared after clicking! This product likely has no images.`);
        log(`       [IMG] Skipping image extraction for this product.`);
        return [];
      }

      log(`       [IMG] ✓ Modal appeared after clicking`);
    } catch (err) {
      logError(`[IMG] Error clicking on product image`, err);
      return [];
    }

    // Get images AFTER clicking - extract ONLY from modal portal
    log(`       [IMG] Extracting images from modal portal...`);
    const modalImages = await page.evaluate(() => {
      const images = [];

      // Look for the modal portal (this is where clicked product images appear)
      const modalPortal = document.querySelector('.ReactModalPortal');
      if (!modalPortal) {
        console.log('[IMG MODAL] ⚠ No modal portal found!');
        return [];
      }

      console.log('[IMG MODAL] ✓ Modal portal found!');

      // Get all swiper slides in the modal (each slide = one image)
      const slides = modalPortal.querySelectorAll('.swiper-slide');
      console.log(`[IMG MODAL] Found ${slides.length} slides in carousel`);

      // If no slides, this modal has no images
      if (slides.length === 0) {
        console.log('[IMG MODAL] ⚠ Modal has no slides! This product has no images.');
        return [];
      }

      // Extract image from each slide
      slides.forEach((slide, idx) => {
        const img = slide.querySelector('img');
        if (img) {
          const src = img.src || img.getAttribute('data-src');
          if (src && src.includes('ic-files-res.cloudinary.com')) {
            // Try to get the best quality image available
            // First, try 1200x1200, if that doesn't exist the Rails service will fall back to what's available
            // Extract current size if present
            const sizeMatch = src.match(/t_t(\d+)x(\d+)v\d+/);
            let finalUrl = src;

            if (sizeMatch) {
              const currentWidth = parseInt(sizeMatch[1]);
              const currentHeight = parseInt(sizeMatch[2]);

              // If current size is small (< 300), try to get larger versions
              if (currentWidth < 300 || currentHeight < 300) {
                // Try 1200x1200 as the preferred size
                finalUrl = src.replace(/t_t\d+x\d+v\d+/, 't_t1200x1200v1');
                console.log(`[IMG MODAL] Slide ${idx + 1}: Upgrading from ${currentWidth}x${currentHeight} to 1200x1200`);
              } else {
                // Current size is >= 300, keep it as-is
                console.log(`[IMG MODAL] Slide ${idx + 1}: Using existing size ${currentWidth}x${currentHeight}`);
              }
            } else {
              // No size transformation in URL, use as-is (original)
              console.log(`[IMG MODAL] Slide ${idx + 1}: Using original image (no size transformation)`);
            }

            if (!images.includes(finalUrl)) {
              images.push(finalUrl);
              const filename = finalUrl.substring(finalUrl.lastIndexOf('/') + 1);
              console.log(`[IMG MODAL] Slide ${idx + 1}: ${filename}`);
            }
          } else {
            console.log(`[IMG MODAL] Slide ${idx + 1}: No valid image src`);
          }
        } else {
          console.log(`[IMG MODAL] Slide ${idx + 1}: No img element found`);
        }
      });

      console.log(`[IMG MODAL] Total images extracted from modal: ${images.length}`);
      return images;
    });

    log(`       [IMG] ========================================`);
    log(`       [IMG] RESULT: Extracted ${modalImages.length} product images from modal`);

    if (modalImages.length === 0) {
      log(`       [IMG] ⚠ WARNING: No images extracted! This product will have no images.`);
    } else {
      modalImages.forEach((img, idx) => {
        const filename = img.substring(img.lastIndexOf('/') + 1);
        log(`       [IMG]   ${idx + 1}. ${filename}`);
      });
    }

    log(`       [IMG] ========================================`);

    // Close modal before moving to next product - CRITICAL for preventing image mismatch
    try {
      log(`       [IMG] Attempting to close modal...`);

      // Try pressing ESC key multiple times to ensure modal closes
      await page.keyboard.press('Escape');
      await page.waitForTimeout(1000);
      await page.keyboard.press('Escape');
      await page.waitForTimeout(1000);

      // Check if modal portal is gone (this is the key check)
      const modalPortalStillExists = await page.locator('.ReactModalPortal').count();
      if (modalPortalStillExists > 0) {
        log(`       [IMG] ⚠ Modal portal still exists after ESC, trying close button...`);

        // Try clicking close button
        const closeButton = page.locator('button[aria-label*="close"], button[aria-label*="Close"], button[data-testid*="close"], .close-button, button.close').first();
        const closeButtonCount = await closeButton.count();
        if (closeButtonCount > 0) {
          log(`       [IMG] Found close button, clicking...`);
          await closeButton.click();
          await page.waitForTimeout(1500);
        } else {
          // Click outside modal as last resort
          log(`       [IMG] No close button, clicking outside modal...`);
          await page.mouse.click(10, 10);
          await page.waitForTimeout(1500);
        }
      }

      // Final check - verify the modal portal is completely gone
      const modalFinalCheck = await page.locator('.ReactModalPortal').count();
      if (modalFinalCheck > 0) {
        log(`       [IMG] ⚠⚠⚠ CRITICAL WARNING: Modal portal still visible after close attempts!`);
        log(`       [IMG] This may cause image mismatch for the next product!`);
        // Extra aggressive close attempt
        await page.keyboard.press('Escape');
        await page.mouse.click(10, 10);
        await page.waitForTimeout(2000);
      } else {
        log(`       [IMG] ✓ Modal closed successfully`);
      }

      // Extra wait to ensure DOM is completely stable before next product
      await page.waitForTimeout(1500);
    } catch (err) {
      logError(`[IMG] Error closing modal`, err);
    }

    return modalImages;

  } catch (error) {
    logError(`[IMG] FATAL ERROR extracting images for product ${productIndex}`, error);
    logError(`[IMG] Stack trace:`, error);
    return [];
  }
}

// Module export for use in Rails ScraperService
if (typeof module !== 'undefined' && module.exports) {
  module.exports = scrapeProducts;
}

// If run directly from command line
if (require.main === module) {
  scrapeProducts().catch(console.error);
}
