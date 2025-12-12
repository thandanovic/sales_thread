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

// Parse existing source_ids to skip re-scraping images/tech description
const EXISTING_SOURCE_IDS = process.env.EXISTING_SOURCE_IDS
  ? new Set(process.env.EXISTING_SOURCE_IDS.split(',').map(id => id.trim()).filter(id => id))
  : new Set();

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
  log(`Existing source_ids to skip (fast mode): ${EXISTING_SOURCE_IDS.size}`);

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
        const sourceId = productData.source_id || productData.sku;
        const isExisting = EXISTING_SOURCE_IDS.has(sourceId);

        log(`      [${scrapedCount + i + 1}/${MAX_PRODUCTS}] Processing: ${productData.title}${isExisting ? ' [FAST MODE - existing]' : ''}`);

        try {
          if (isExisting) {
            // FAST MODE: Skip expensive image and tech description extraction
            // Rails will preserve existing data for these products
            log(`       ⚡ Skipping image/tech extraction (product exists in database)`);
            productData.images = [];
            productData.technical_description = null;
            productData.models = null;
            productData.reuse_existing = true;
          } else {
            // FULL MODE: Extract images and technical description for new products
            // Extract images using the imageContainerIndex stored during product extraction
            // This ensures we click on the exact same container that corresponds to this product
            const images = await extractImagesFromProductCard(page, productData.imageContainerIndex);
            productData.images = images;

            log(`       ✓ Extracted ${images.length} images without leaving listing page`);

            // Extract technical description by clicking "Više informacija" button
            const techData = await extractTechnicalDescription(page, productData.imageContainerIndex);
            productData.technical_description = techData.technical_description;
            productData.models = techData.models;

            if (techData.technical_description) {
              log(`       ✓ Extracted technical description`);
            }
            if (techData.models) {
              log(`       ✓ Extracted models: ${techData.models.substring(0, 50)}...`);
            }

            productData.reuse_existing = false;
          }

          // Remove the temporary imageContainerIndex before saving
          delete productData.imageContainerIndex;

          products.push(productData);
          scrapedCount++;
        } catch (error) {
          logError(`Failed to extract images for product ${i}`, error);
          // Still add product without images
          productData.images = [];
          productData.reuse_existing = isExisting;

          // Remove the temporary imageContainerIndex before saving
          delete productData.imageContainerIndex;

          products.push(productData);
          scrapedCount++;
        }

        // Small delay between products (shorter for fast mode)
        if (i < productsToProcess.length - 1) {
          await page.waitForTimeout(isExisting ? 100 : 500);
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

      // Extract subtitle/B2BName (product category description)
      // This is found in the same product card as the title
      let subTitle = null;

      // Extract specs/description from productAttributes section
      let description = null;
      let specs = {};

      // Try to find productAttributes container for this product
      // Navigate up from the link to find the product card that contains attributes
      let productCard = link;
      for (let i = 0; i < 15; i++) {
        productCard = productCard.parentElement;
        if (!productCard) break;

        // Extract subtitle/B2BName from this product card
        const subTitleEl = productCard.querySelector('[data-testid="B2BName-new"]');
        if (subTitleEl && !subTitle) {
          subTitle = subTitleEl.textContent.trim();
          console.log(`[EXTRACTION] Found subtitle for product ${realProductIndex}: ${subTitle}`);
        }

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
      console.log(`[EXTRACTION]   - Subtitle: ${subTitle || 'NOT FOUND'}`);
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
          sub_title: subTitle || null,
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

/**
 * Extract technical description by clicking "Više informacija" button
 * Also extracts models from the technical description (text after "odgovara:")
 *
 * @param page - Playwright page object
 * @param containerIndex - The index of the product card container
 * @returns {Object} { technical_description, models }
 */
async function extractTechnicalDescription(page, containerIndex) {
  try {
    log(`       [TECH] Extracting technical description for container ${containerIndex}...`);

    if (containerIndex === -1) {
      log(`       [TECH] Container index is -1, skipping technical description extraction`);
      return { technical_description: null, models: null };
    }

    // Get all product cards on the page - need to find the expand button within the right product
    const allProductCards = await page.locator('[data-testid="productIndexLink"]').all();

    if (containerIndex >= allProductCards.length) {
      log(`       [TECH] Container index ${containerIndex} out of bounds (${allProductCards.length} products)`);
      return { technical_description: null, models: null };
    }

    // Find the product card container by traversing up from the product link
    const productLink = allProductCards[containerIndex];

    // Navigate up to find the parent container that has the expand button
    // The expand button is in the same row/card as the product link
    const expandButton = page.locator('[data-testid="expandButton-MoreInfo"]').nth(containerIndex);
    const expandButtonCount = await expandButton.count();

    if (expandButtonCount === 0) {
      log(`       [TECH] No "Više informacija" button found for this product`);
      return { technical_description: null, models: null };
    }

    log(`       [TECH] Found expand button, clicking...`);

    // Scroll the button into view first
    await expandButton.scrollIntoViewIfNeeded();
    await page.waitForTimeout(300);

    // Click to expand
    await expandButton.click();
    await page.waitForTimeout(1500);

    // Wait for the expanded section to appear - it should be visible now after clicking
    // The expanded section appears as a child/sibling of the clicked product row
    await page.waitForSelector('[data-testid="productAdditionalInfo"]', { timeout: 3000 }).catch(() => {});

    // Extract the technical description text - look for the VISIBLE expanded section
    // Since only one section is expanded at a time, we find the one that's currently visible
    const techDescData = await page.evaluate(() => {
      // Find all expanded sections - there should only be one visible at a time
      const expandedSections = document.querySelectorAll('[data-testid="productAdditionalInfo"]');

      // Find the visible/expanded section (check if it's inside an expanded-section container)
      let section = null;
      for (const sec of expandedSections) {
        // Check if this section is visible (has dimensions)
        const rect = sec.getBoundingClientRect();
        if (rect.height > 0 && rect.width > 0) {
          section = sec;
          break;
        }
      }

      if (!section) {
        console.log('[TECH] No visible expanded section found');
        return { technical_description: null, models: null };
      }

      // Look for "Tehnički opis" section
      let technicalDescription = null;
      let models = null;

      // Strategy 1: Find the "Tehnički opis" label and get its sibling content
      // Structure: <div>Tehnički opis</div><div class="cOZxao"><div class="klTUHd">ACTUAL TEXT</div></div>
      const allDivs = section.querySelectorAll('div');
      for (const div of allDivs) {
        // Check if this div contains exactly "Tehnički opis" as its direct text
        if (div.childNodes.length === 1 &&
            div.childNodes[0].nodeType === Node.TEXT_NODE &&
            div.textContent.trim() === 'Tehnički opis') {

          // Found the label, now get the sibling container with the actual description
          const nextSibling = div.nextElementSibling;
          if (nextSibling) {
            // The description is in a nested div (class klTUHd inside cOZxao)
            const innerDiv = nextSibling.querySelector('div');
            if (innerDiv) {
              technicalDescription = innerDiv.textContent.trim();
            } else {
              technicalDescription = nextSibling.textContent.trim();
            }
            console.log('[TECH] Found via label sibling:', technicalDescription.substring(0, 100));
            break;
          }
        }
      }

      // Strategy 2: If not found, try finding by class structure
      if (!technicalDescription) {
        // Look for div.cOZxao containing div.klTUHd
        const cOZxaoDiv = section.querySelector('.cOZxao');
        if (cOZxaoDiv) {
          const klTUHdDiv = cOZxaoDiv.querySelector('.klTUHd');
          if (klTUHdDiv) {
            technicalDescription = klTUHdDiv.textContent.trim();
            console.log('[TECH] Found via class structure:', technicalDescription.substring(0, 100));
          }
        }
      }

      // Strategy 3: Last resort - find any text containing "odgovara:"
      if (!technicalDescription) {
        for (const div of allDivs) {
          const text = div.textContent.trim();
          if (text.includes('odgovara:') && !text.includes('Tehnički opis') && !text.includes('TecDoc')) {
            technicalDescription = text;
            console.log('[TECH] Found via odgovara search:', technicalDescription.substring(0, 100));
            break;
          }
        }
      }

      // Extract models from technical description
      // Strategy 1: Look for "odgovara:" pattern
      if (technicalDescription) {
        const odgovaraMatch = technicalDescription.match(/odgovara:\s*(.+)$/i);
        if (odgovaraMatch) {
          models = odgovaraMatch[1].trim();
          console.log('[TECH] Extracted models via "odgovara:":', models);
        }
      }

      // Strategy 2: Look for "Vozila:" pattern
      if (!models && technicalDescription) {
        const vozilaMatch = technicalDescription.match(/Vozila:\s*(.+?)(?:$|,\s*[A-Z][a-z]+:)/i);
        if (vozilaMatch) {
          models = vozilaMatch[1].trim();
          console.log('[TECH] Extracted models via "Vozila:":', models);
        }
      }

      // Strategy 2b: Look for "kočioni sustav:" or "kočioni sistem:" pattern
      // Extract the text after "sustav: BRAND;" which often contains vehicle models
      if (!models && technicalDescription) {
        const sustavMatch = technicalDescription.match(/ko[čc]ioni\s+s[ui]stav[a]?\s*:\s*\w+\s*[;,]\s*(.+)$/i);
        if (sustavMatch) {
          // The text after brake brand often contains vehicle models
          // Will be processed by Strategy 3 below
          console.log('[TECH] Found text after brake system:', sustavMatch[1].substring(0, 50));
        }
      }

      // Strategy 3: Look for car manufacturer names directly in the text
      // This handles formats like "ALFA ROMEO TONALE; FIAT 500X; JEEP COMPASS"
      // Also handles mixed case like "Audi 80 (B4)"
      if (!models && technicalDescription) {
        const carManufacturers = [
          'ALFA ROMEO', 'AUDI', 'BMW', 'CITROEN', 'CITROËN', 'DACIA', 'FIAT', 'FORD', 'HONDA',
          'HYUNDAI', 'JEEP', 'KIA', 'LANCIA', 'MAZDA', 'MERCEDES', 'MINI', 'MITSUBISHI',
          'NISSAN', 'OPEL', 'PEUGEOT', 'RENAULT', 'SEAT', 'SKODA', 'ŠKODA', 'SUZUKI', 'TOYOTA',
          'VOLKSWAGEN', 'VW', 'VOLVO', 'CHEVROLET', 'CHRYSLER', 'DODGE', 'PORSCHE',
          'SAAB', 'SUBARU', 'LAND ROVER', 'JAGUAR', 'LEXUS', 'INFINITI', 'CADILLAC',
          'TESLA', 'ISUZU', 'LADA', 'DAEWOO', 'SSANGYONG', 'SMART', 'ROVER', 'MG',
          'TRABANT', 'WARTBURG', 'ZASTAVA', 'YUGO'
        ];

        // Common model names often used without manufacturer prefix
        // Format: { pattern: 'MODEL', manufacturer: 'MANUFACTURER' }
        const standaloneModels = [
          // VW models
          { pattern: 'GOLF', manufacturer: 'VW' },
          { pattern: 'PASSAT', manufacturer: 'VW' },
          { pattern: 'POLO', manufacturer: 'VW' },
          { pattern: 'TIGUAN', manufacturer: 'VW' },
          { pattern: 'TOURAN', manufacturer: 'VW' },
          { pattern: 'TOUAREG', manufacturer: 'VW' },
          { pattern: 'CADDY', manufacturer: 'VW' },
          { pattern: 'TRANSPORTER', manufacturer: 'VW' },
          { pattern: 'SHARAN', manufacturer: 'VW' },
          { pattern: 'ARTEON', manufacturer: 'VW' },
          { pattern: 'JETTA', manufacturer: 'VW' },
          { pattern: 'BEETLE', manufacturer: 'VW' },
          { pattern: 'SCIROCCO', manufacturer: 'VW' },
          // Opel models
          { pattern: 'ASTRA', manufacturer: 'OPEL' },
          { pattern: 'CORSA', manufacturer: 'OPEL' },
          { pattern: 'VECTRA', manufacturer: 'OPEL' },
          { pattern: 'INSIGNIA', manufacturer: 'OPEL' },
          { pattern: 'ZAFIRA', manufacturer: 'OPEL' },
          { pattern: 'MERIVA', manufacturer: 'OPEL' },
          { pattern: 'MOKKA', manufacturer: 'OPEL' },
          // Ford models
          { pattern: 'FOCUS', manufacturer: 'FORD' },
          { pattern: 'FIESTA', manufacturer: 'FORD' },
          { pattern: 'MONDEO', manufacturer: 'FORD' },
          { pattern: 'KUGA', manufacturer: 'FORD' },
          { pattern: 'ESCORT', manufacturer: 'FORD' },
          // Fiat models
          { pattern: 'PUNTO', manufacturer: 'FIAT' },
          { pattern: 'PANDA', manufacturer: 'FIAT' },
          { pattern: 'BRAVO', manufacturer: 'FIAT' },
          { pattern: 'STILO', manufacturer: 'FIAT' },
          { pattern: 'TIPO', manufacturer: 'FIAT' },
          { pattern: 'MULTIPLA', manufacturer: 'FIAT' },
          // Renault models
          { pattern: 'CLIO', manufacturer: 'RENAULT' },
          { pattern: 'MEGANE', manufacturer: 'RENAULT' },
          { pattern: 'SCENIC', manufacturer: 'RENAULT' },
          { pattern: 'LAGUNA', manufacturer: 'RENAULT' },
          { pattern: 'CAPTUR', manufacturer: 'RENAULT' },
          // Peugeot uses numbers, skip
          // Citroen models
          { pattern: 'BERLINGO', manufacturer: 'CITROEN' },
          { pattern: 'XSARA', manufacturer: 'CITROEN' },
          { pattern: 'SAXO', manufacturer: 'CITROEN' },
          // Jeep models
          { pattern: 'COMPASS', manufacturer: 'JEEP' },
          { pattern: 'RENEGADE', manufacturer: 'JEEP' },
          { pattern: 'CHEROKEE', manufacturer: 'JEEP' },
          { pattern: 'WRANGLER', manufacturer: 'JEEP' },
          // Seat models
          { pattern: 'IBIZA', manufacturer: 'SEAT' },
          { pattern: 'LEON', manufacturer: 'SEAT' },
          { pattern: 'TOLEDO', manufacturer: 'SEAT' },
          { pattern: 'ALTEA', manufacturer: 'SEAT' },
          // Skoda models
          { pattern: 'OCTAVIA', manufacturer: 'SKODA' },
          { pattern: 'FABIA', manufacturer: 'SKODA' },
          { pattern: 'SUPERB', manufacturer: 'SKODA' },
          { pattern: 'RAPID', manufacturer: 'SKODA' },
          { pattern: 'YETI', manufacturer: 'SKODA' },
          // Toyota models
          { pattern: 'COROLLA', manufacturer: 'TOYOTA' },
          { pattern: 'YARIS', manufacturer: 'TOYOTA' },
          { pattern: 'AVENSIS', manufacturer: 'TOYOTA' },
          { pattern: 'RAV4', manufacturer: 'TOYOTA' },
          { pattern: 'AURIS', manufacturer: 'TOYOTA' },
          // Honda models
          { pattern: 'CIVIC', manufacturer: 'HONDA' },
          { pattern: 'ACCORD', manufacturer: 'HONDA' },
          { pattern: 'CR-V', manufacturer: 'HONDA' },
          { pattern: 'JAZZ', manufacturer: 'HONDA' },
          // Mazda models
          { pattern: 'MAZDA3', manufacturer: 'MAZDA' },
          { pattern: 'MAZDA6', manufacturer: 'MAZDA' },
          { pattern: 'CX-5', manufacturer: 'MAZDA' },
          // Nissan models
          { pattern: 'QASHQAI', manufacturer: 'NISSAN' },
          { pattern: 'JUKE', manufacturer: 'NISSAN' },
          { pattern: 'MICRA', manufacturer: 'NISSAN' },
          { pattern: 'X-TRAIL', manufacturer: 'NISSAN' },
          // Hyundai models
          { pattern: 'TUCSON', manufacturer: 'HYUNDAI' },
          { pattern: 'I30', manufacturer: 'HYUNDAI' },
          { pattern: 'I20', manufacturer: 'HYUNDAI' },
          { pattern: 'SANTA FE', manufacturer: 'HYUNDAI' },
          // Kia models
          { pattern: 'SPORTAGE', manufacturer: 'KIA' },
          { pattern: 'CEED', manufacturer: 'KIA' },
          { pattern: 'RIO', manufacturer: 'KIA' },
          { pattern: 'SORENTO', manufacturer: 'KIA' },
          // Alfa Romeo models
          { pattern: 'GIULIETTA', manufacturer: 'ALFA ROMEO' },
          { pattern: 'GIULIA', manufacturer: 'ALFA ROMEO' },
          { pattern: 'STELVIO', manufacturer: 'ALFA ROMEO' },
          { pattern: 'TONALE', manufacturer: 'ALFA ROMEO' },
          { pattern: '147', manufacturer: 'ALFA ROMEO' },
          { pattern: '156', manufacturer: 'ALFA ROMEO' },
          { pattern: '159', manufacturer: 'ALFA ROMEO' },
        ];

        const foundModels = [];

        // Find all manufacturer mentions and extract the following model info (case-insensitive)
        for (const manufacturer of carManufacturers) {
          // Case-insensitive regex to match manufacturer followed by model info
          // Allow commas within date ranges like "10,96" or "-10,96" but stop at "; " or ", " followed by uppercase
          // Pattern: manufacturer + model info until semicolon or comma followed by space and uppercase letter
          const regex = new RegExp('\\b' + manufacturer + '\\s+([^;]+?)(?=;|,\\s*[A-Z]|$)', 'gi');
          let match;
          while ((match = regex.exec(technicalDescription)) !== null) {
            // Preserve original case from the text
            const fullMatch = match[0].trim();
            // Clean up trailing commas or spaces
            const cleanMatch = fullMatch.replace(/[,\s]+$/, '');
            if (cleanMatch.length > manufacturer.length + 1 && !foundModels.some(m => m.toUpperCase() === cleanMatch.toUpperCase())) {
              foundModels.push(cleanMatch);
            }
          }
        }

        // Also search for standalone model names (like "Golf VI" without "VW")
        for (const model of standaloneModels) {
          // Match model name followed by any info (version, year, engine, etc.)
          // Stop at semicolon or comma followed by uppercase letter (next model/manufacturer)
          const regex = new RegExp('\\b' + model.pattern + '\\s+([^;]+?)(?=;|,\\s*[A-Z]|$)', 'gi');
          let match;
          while ((match = regex.exec(technicalDescription)) !== null) {
            // Prefix with manufacturer for clarity
            const fullMatch = model.manufacturer + ' ' + match[0].trim().replace(/[,\s]+$/, '');
            // Avoid duplicates and skip if already matched by manufacturer search
            if (!foundModels.some(m => m.toUpperCase() === fullMatch.toUpperCase()) &&
                !foundModels.some(m => m.toUpperCase().includes(match[0].trim().toUpperCase()))) {
              foundModels.push(fullMatch);
            }
          }
        }

        if (foundModels.length > 0) {
          models = foundModels.join('; ');
          console.log('[TECH] Extracted models via manufacturer search:', models);
        }
      }

      return { technical_description: technicalDescription, models: models };
    });

    log(`       [TECH] Technical description: ${techDescData.technical_description ? 'FOUND (' + techDescData.technical_description.substring(0, 50) + '...)' : 'NOT FOUND'}`);
    log(`       [TECH] Models: ${techDescData.models ? techDescData.models.substring(0, 50) + '...' : 'NOT FOUND'}`);

    // Click to collapse the section
    try {
      await expandButton.click();
      await page.waitForTimeout(500);
    } catch (e) {
      // Ignore collapse errors
    }

    return techDescData;

  } catch (error) {
    logError(`[TECH] Error extracting technical description`, error);
    return { technical_description: null, models: null };
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
