/**
 * Product Page Exploration Script
 *
 * This script logs in to Intercars and analyzes the product listing page to understand:
 * - Product card structure
 * - Pagination mechanism
 * - Image URL patterns
 * - Data extraction strategy
 */

const { chromium } = require('playwright-extra');
const stealth = require('puppeteer-extra-plugin-stealth');
const fs = require('fs');
require('dotenv').config();

// Add stealth plugin to avoid detection
chromium.use(stealth());

const PRODUCT_URL = process.env.PRODUCT_URL || 'https://ba.e-cat.intercars.eu/bs/Cijela-ponuda/Gume-Točkovi-Pribor/Gume/Putničke-gume/c/tecdoc-5090008-5010105-5010106?q=%3Adefault%3AbranchAvailability%3AALL%3AproductBrandCode%3Aicgoods_2252&sort=default';

async function exploreProductPage() {
  console.log('🔍 Intercars Product Page Explorer (with Stealth Mode)\n');
  console.log(`Target URL: ${PRODUCT_URL}\n`);

  if (!process.env.INTERCARS_USERNAME || !process.env.INTERCARS_PASSWORD) {
    console.error('❌ Error: Please set credentials in .env file');
    return;
  }

  const browser = await chromium.launch({
    headless: false, // Run in headed mode to better bypass Cloudflare
    slowMo: 50, // Slow down operations to appear more human
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

  // Track network requests for images
  const imageRequests = [];
  page.on('request', request => {
    if (request.resourceType() === 'image') {
      imageRequests.push(request.url());
    }
  });

  try {
    // Step 1: Navigate and login
    console.log('🔐 Step 1: Logging in to Intercars...\n');

    await page.goto('https://ba.e-cat.intercars.eu/bs/', { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(2000);

    console.log(`   Initial URL: ${page.url()}`);

    // Check if we're on SSO login page
    if (page.url().includes('account.intercars.eu') && page.url().includes('login')) {
      console.log('   Detected SSO login page - TWO-STEP LOGIN FLOW\n');

      // STEP 1: Enter email/username
      console.log('   Step 1a: Looking for email field...');
      const emailField = page.locator('input#usernameUserInput').first();

      if (await emailField.count() > 0) {
        await emailField.fill(process.env.INTERCARS_USERNAME);
        console.log(`   ✓ Email entered: ${process.env.INTERCARS_USERNAME}`);

        await page.screenshot({ path: 'screenshots/explore-01-email-entered.png' });

        // Submit email form
        const continueButton = page.locator('input[type="submit"]').first();
        if (await continueButton.count() > 0) {
          await continueButton.click();
          console.log('   ✓ Continue button clicked\n');

          await page.waitForTimeout(3000);
          await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});
        }
      }

      // STEP 2: Enter password (should be on password page now)
      console.log('   Step 1b: Looking for password field...');
      const passwordField = page.locator('input[type="password"]').first();

      if (await passwordField.count() > 0) {
        await passwordField.fill(process.env.INTERCARS_PASSWORD);
        console.log('   ✓ Password entered');

        await page.screenshot({ path: 'screenshots/explore-02-password-entered.png' });

        // Submit password form
        const signInButton = page.locator('button[type="submit"], input[type="submit"]').first();
        if (await signInButton.count() > 0) {
          await signInButton.click();
          console.log('   ✓ Sign in button clicked\n');

          await page.waitForTimeout(3000);
          await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});

          console.log(`   ✓ After login URL: ${page.url()}\n`);
          await page.screenshot({ path: 'screenshots/explore-03-after-login.png', fullPage: true });
        }
      } else {
        console.log('   ⚠️  Password field not found - may still be on email step or login failed');
        await page.screenshot({ path: 'screenshots/explore-login-stuck.png', fullPage: true });
      }
    }

    // Step 2: Navigate to product page
    console.log('📄 Step 2: Navigating to product listing page...\n');

    await page.goto(PRODUCT_URL, { waitUntil: 'domcontentloaded', timeout: 30000 });

    // Wait for Cloudflare challenge to complete
    console.log('   Waiting for Cloudflare challenge to pass...');

    // Wait for the page to actually load (title should change from "Just a moment...")
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

    // Wait for React microfrontend to load products
    console.log('   Waiting for React app to load products...');

    // Wait for product tiles to appear
    try {
      await page.waitForSelector('[data-testid*="product"], .product-tile, [class*="ProductTile"]', { timeout: 15000 });
      console.log('   ✓ Products loaded!\n');
    } catch (e) {
      console.log('   ⚠️  Products may not have loaded yet, waiting additional time...');
      await page.waitForTimeout(5000);
    }

    await page.screenshot({ path: 'screenshots/explore-04-product-page.png', fullPage: true });

    // Step 3: Analyze page structure
    console.log('🔬 Step 3: Analyzing page structure...\n');

    const pageAnalysis = await page.evaluate(() => {
      const analysis = {
        pageTitle: document.title,
        productCards: [],
        pagination: {
          found: false,
          type: null,
          details: {}
        },
        images: [],
        potentialSelectors: {
          productCard: [],
          productLink: [],
          productImage: [],
          productTitle: [],
          productPrice: [],
          pagination: []
        }
      };

      // Detect product cards using various strategies
      const cardSelectors = [
        '[data-testid*="product"]',
        '[data-testid*="tile"]',
        '.product-tile',
        '[class*="ProductTile"]',
        '.product-card',
        '.product-item',
        '[class*="product-"]',
        'article',
        '[data-product]',
        '.item'
      ];

      for (const selector of cardSelectors) {
        const elements = document.querySelectorAll(selector);
        if (elements.length > 0) {
          analysis.potentialSelectors.productCard.push({
            selector: selector,
            count: elements.length
          });
        }
      }

      // Detect pagination
      const paginationSelectors = [
        '.pagination',
        '[class*="pagination"]',
        '[class*="pager"]',
        'nav[aria-label*="page"]',
        '.page-numbers',
        '[role="navigation"] a[href*="page"]'
      ];

      for (const selector of paginationSelectors) {
        const elements = document.querySelectorAll(selector);
        if (elements.length > 0) {
          analysis.pagination.found = true;
          analysis.pagination.type = selector;

          const links = Array.from(elements[0].querySelectorAll('a')).map(a => ({
            text: a.textContent.trim(),
            href: a.getAttribute('href')
          }));

          analysis.pagination.details = {
            linkCount: links.length,
            links: links.slice(0, 5)  // First 5 links
          };

          analysis.potentialSelectors.pagination.push({
            selector: selector,
            count: elements.length
          });
          break;
        }
      }

      // Extract first few product cards for analysis
      const productElements = document.querySelectorAll('[class*="product"], article, .item');
      for (let i = 0; i < Math.min(5, productElements.length); i++) {
        const el = productElements[i];

        const card = {
          outerHTML: el.outerHTML.substring(0, 500),
          classes: el.className,
          dataAttrs: {},
          links: [],
          images: [],
          textContent: el.textContent.trim().substring(0, 200)
        };

        // Extract data attributes
        for (const attr of el.attributes) {
          if (attr.name.startsWith('data-')) {
            card.dataAttrs[attr.name] = attr.value;
          }
        }

        // Extract links
        const links = el.querySelectorAll('a');
        links.forEach(a => {
          card.links.push({
            href: a.getAttribute('href'),
            text: a.textContent.trim().substring(0, 50)
          });
        });

        // Extract images
        const images = el.querySelectorAll('img');
        images.forEach(img => {
          const imgData = {
            src: img.src,
            dataSrc: img.getAttribute('data-src'),
            alt: img.alt,
            class: img.className
          };
          card.images.push(imgData);

          // Add to global images list
          if (img.src) analysis.images.push(img.src);
          if (img.getAttribute('data-src')) analysis.images.push(img.getAttribute('data-src'));
        });

        analysis.productCards.push(card);
      }

      // Detect potential image selectors
      const imgSelectors = [
        '.product-image img',
        '[class*="product"] img',
        'article img',
        '.item img',
        'img[class*="product"]'
      ];

      for (const selector of imgSelectors) {
        const images = document.querySelectorAll(selector);
        if (images.length > 0) {
          analysis.potentialSelectors.productImage.push({
            selector: selector,
            count: images.length
          });
        }
      }

      // Detect potential title selectors
      const titleSelectors = [
        '.product-title',
        '.product-name',
        '[class*="product"] h2',
        '[class*="product"] h3',
        'article h2',
        'article h3'
      ];

      for (const selector of titleSelectors) {
        const titles = document.querySelectorAll(selector);
        if (titles.length > 0) {
          analysis.potentialSelectors.productTitle.push({
            selector: selector,
            count: titles.length
          });
        }
      }

      // Detect potential price selectors
      const priceSelectors = [
        '.price',
        '[class*="price"]',
        '[data-price]',
        '[itemprop="price"]'
      ];

      for (const selector of priceSelectors) {
        const prices = document.querySelectorAll(selector);
        if (prices.length > 0) {
          analysis.potentialSelectors.productPrice.push({
            selector: selector,
            count: prices.length
          });
        }
      }

      return analysis;
    });

    // Save page HTML for manual inspection
    const html = await page.content();
    fs.writeFileSync('data/product-page.html', html);

    // Generate detailed report
    const report = {
      timestamp: new Date().toISOString(),
      productUrl: PRODUCT_URL,
      currentUrl: page.url(),
      analysis: pageAnalysis,
      imageRequests: imageRequests.slice(0, 20), // First 20 image requests
      recommendations: []
    };

    // Generate recommendations
    if (pageAnalysis.potentialSelectors.productCard.length > 0) {
      const topSelector = pageAnalysis.potentialSelectors.productCard[0];
      report.recommendations.push({
        type: 'Product Card Selector',
        selector: topSelector.selector,
        count: topSelector.count,
        confidence: 'high'
      });
    }

    if (pageAnalysis.pagination.found) {
      report.recommendations.push({
        type: 'Pagination',
        method: 'Link-based navigation',
        selector: pageAnalysis.pagination.type,
        details: pageAnalysis.pagination.details
      });
    }

    if (pageAnalysis.potentialSelectors.productImage.length > 0) {
      report.recommendations.push({
        type: 'Product Images',
        selectors: pageAnalysis.potentialSelectors.productImage
      });
    }

    // Save report
    fs.writeFileSync('data/exploration-report.json', JSON.stringify(report, null, 2));

    // Print summary
    console.log('═══════════════════════════════════════════════════════════');
    console.log('                    EXPLORATION RESULTS                     ');
    console.log('═══════════════════════════════════════════════════════════\n');

    console.log(`📄 Page Title: ${pageAnalysis.pageTitle}\n`);

    console.log('🎯 PRODUCT CARDS:');
    if (pageAnalysis.potentialSelectors.productCard.length > 0) {
      pageAnalysis.potentialSelectors.productCard.forEach(s => {
        console.log(`   ✓ ${s.selector} - Found ${s.count} elements`);
      });
    } else {
      console.log('   ❌ No product cards detected');
    }

    console.log('\n📸 PRODUCT IMAGES:');
    if (pageAnalysis.potentialSelectors.productImage.length > 0) {
      pageAnalysis.potentialSelectors.productImage.forEach(s => {
        console.log(`   ✓ ${s.selector} - Found ${s.count} images`);
      });

      if (pageAnalysis.productCards.length > 0 && pageAnalysis.productCards[0].images.length > 0) {
        console.log('\n   Sample image from first product:');
        const sampleImg = pageAnalysis.productCards[0].images[0];
        console.log(`   - src: ${sampleImg.src || '(none)'}`);
        console.log(`   - data-src: ${sampleImg.dataSrc || '(none)'}`);
        console.log(`   - alt: ${sampleImg.alt || '(none)'}`);
      }
    } else {
      console.log('   ❌ No product images detected');
    }

    console.log('\n📖 PAGINATION:');
    if (pageAnalysis.pagination.found) {
      console.log(`   ✓ Pagination detected: ${pageAnalysis.pagination.type}`);
      console.log(`   ✓ Number of page links: ${pageAnalysis.pagination.details.linkCount}`);
      if (pageAnalysis.pagination.details.links) {
        console.log('   Sample links:');
        pageAnalysis.pagination.details.links.forEach(link => {
          console.log(`     - "${link.text}" → ${link.href}`);
        });
      }
    } else {
      console.log('   ⚠️  No pagination detected - may use infinite scroll or load more button');
    }

    console.log('\n💾 FILES SAVED:');
    console.log('   - data/exploration-report.json (Full analysis)');
    console.log('   - data/product-page.html (Page HTML)');
    console.log('   - screenshots/explore-04-product-page.png (Screenshot)');

    console.log('\n═══════════════════════════════════════════════════════════\n');

    // Step 4: Try to click next page if pagination exists
    if (pageAnalysis.pagination.found) {
      console.log('🔄 Step 4: Testing pagination...\n');

      try {
        const nextButton = await page.locator('a:has-text("Next"), a:has-text("Sljedeća"), a[aria-label*="Next"], .pagination a:last-child').first();

        if (await nextButton.count() > 0) {
          console.log('   ✓ Found "Next" button, clicking...');
          await nextButton.click();
          await page.waitForTimeout(3000);
          await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});

          console.log(`   ✓ Navigated to: ${page.url()}`);
          await page.screenshot({ path: 'screenshots/explore-05-page-2.png', fullPage: true });

          // Check if products changed
          const page2Analysis = await page.evaluate(() => {
            return {
              productCount: document.querySelectorAll('[class*="product"], article, .item').length,
              firstProductText: document.querySelector('[class*="product"], article, .item')?.textContent.trim().substring(0, 100)
            };
          });

          console.log(`   ✓ Page 2 has ${page2Analysis.productCount} products`);
          console.log('   ✓ Pagination working!\n');
        }
      } catch (error) {
        console.log(`   ⚠️  Could not test pagination: ${error.message}\n`);
      }
    }

  } catch (error) {
    console.error('\n❌ Error during exploration:', error.message);
    console.error(error.stack);
    await page.screenshot({ path: 'screenshots/error-explore.png' });
  } finally {
    await browser.close();
    console.log('✅ Exploration complete!\n');
  }
}

exploreProductPage().catch(console.error);
