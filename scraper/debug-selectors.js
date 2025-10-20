/**
 * Debug script to see what selectors are finding on the page
 */

const { chromium } = require('playwright-extra');
const stealth = require('puppeteer-extra-plugin-stealth');
require('dotenv').config();

chromium.use(stealth());

const SITE_URL = 'https://ba.e-cat.intercars.eu/bs/';
const PRODUCT_URL = process.env.PRODUCT_URL || 'https://ba.e-cat.intercars.eu/bs/Cijela-ponuda/Gume-Točkovi-Pribor/Gume/Putničke-gume/c/tecdoc-5090008-5010105-5010106?q=%3Adefault-m%3AbranchAvailability%3AALL%3AproductBrandCode%3Aicgoods_2203%3AproductBrandCode%3Aicgoods_2431%3Aicgoods_63841%3Aicgoods_1028867';

async function debugSelectors() {
  console.log('🔍 Debugging Selectors...\n');

  const browser = await chromium.launch({
    headless: false,
    slowMo: 50
  });

  const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    viewport: { width: 1920, height: 1080 }
  });

  const page = await context.newPage();

  try {
    // Login
    console.log('🔐 Logging in...\n');
    await page.goto(SITE_URL, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(2000);

    if (page.url().includes('account.intercars.eu') && page.url().includes('login')) {
      const emailField = page.locator('input#usernameUserInput').first();
      if (await emailField.count() > 0) {
        await emailField.fill(process.env.INTERCARS_USERNAME);
        const continueButton = page.locator('input[type="submit"]').first();
        if (await continueButton.count() > 0) {
          await continueButton.click();
          await page.waitForTimeout(3000);
        }
      }

      const passwordField = page.locator('input[type="password"]').first();
      if (await passwordField.count() > 0) {
        await passwordField.fill(process.env.INTERCARS_PASSWORD);
        const signInButton = page.locator('button[type="submit"], input[type="submit"]').first();
        if (await signInButton.count() > 0) {
          await signInButton.click();
          await page.waitForTimeout(3000);
        }
      }
    }

    // Navigate to product page
    console.log('📄 Navigating to product page...\n');
    await page.goto(PRODUCT_URL, { waitUntil: 'domcontentloaded', timeout: 30000 });

    // Wait for Cloudflare
    try {
      await page.waitForFunction(() => !document.title.includes('Just a moment'), { timeout: 30000 });
    } catch (e) {}

    await page.waitForTimeout(5000);

    // Test different selectors
    console.log('🔬 Testing selectors...\n');

    const results = await page.evaluate(() => {
      const info = {
        url: window.location.href,
        title: document.title,
        selectors: {}
      };

      // Test various selectors
      const selectorsToTest = [
        '[data-testid="productIndexLink"]',
        '[data-test="productIndexLink"]',
        'a[href*="/product/"]',
        'a[data-towkod]',
        '[class*="product"]',
        '[data-testid*="product"]'
      ];

      selectorsToTest.forEach(selector => {
        const elements = document.querySelectorAll(selector);
        const matches = [];

        elements.forEach((el, idx) => {
          if (idx < 5) { // Only first 5
            matches.push({
              tag: el.tagName,
              href: el.href || null,
              title: el.getAttribute('title') || el.textContent?.trim().substring(0, 50) || '',
              sku: el.getAttribute('data-towkod') || null,
              classes: el.className
            });
          }
        });

        info.selectors[selector] = {
          count: elements.length,
          samples: matches
        };
      });

      return info;
    });

    console.log('Results:\n');
    console.log(JSON.stringify(results, null, 2));

    console.log('\n\n⏸️  Browser will stay open for 30 seconds for manual inspection...');
    await page.waitForTimeout(30000);

  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await browser.close();
  }
}

debugSelectors().catch(console.error);
