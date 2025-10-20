const { chromium } = require('playwright-extra');
const stealth = require('puppeteer-extra-plugin-stealth');
chromium.use(stealth());
require('dotenv').config();

(async () => {
  const browser = await chromium.launch({ headless: false, slowMo: 100 });
  const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    viewport: { width: 1920, height: 1080 }
  });
  const page = await context.newPage();

  page.on('console', msg => console.log('[Browser]:', msg.text()));

  console.log('Logging in...');
  await page.goto('https://ba.e-cat.intercars.eu/bs/', { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(2000);

  if (page.url().includes('account.intercars.eu')) {
    await page.locator('input#usernameUserInput').first().fill(process.env.INTERCARS_USERNAME);
    await page.locator('input[type="submit"]').first().click();
    await page.waitForTimeout(3000);
    await page.locator('input[type="password"]').first().fill(process.env.INTERCARS_PASSWORD);
    await page.locator('button[type="submit"], input[type="submit"]').first().click();
    await page.waitForTimeout(3000);
  }

  console.log('Going to product listing...');
  await page.goto(process.env.PRODUCT_URL, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(3000);
  await page.waitForSelector('[data-testid="productIndexLink"]', { timeout: 15000 });

  console.log('Testing price extraction...');
  const result = await page.evaluate(() => {
    const links = document.querySelectorAll('[data-testid="productIndexLink"]');
    console.log(`Found ${links.length} product links`);

    const firstLink = links[0];
    if (!firstLink) return { error: 'No product links found' };

    const sku = firstLink.getAttribute('data-towkod');
    console.log(`First product SKU: ${sku}`);

    // Try different parent finding strategies
    const strategies = [];

    let current = firstLink;
    for (let i = 0; i < 6; i++) {
      current = current.parentElement;
      if (!current) break;

      const priceEl = current.querySelector('[data-testid="wholesalePrice-new"], [data-test="wholesalePrice-new"]');
      strategies.push({
        level: i + 1,
        tagName: current.tagName,
        className: current.className,
        foundPrice: !!priceEl,
        dataAttr: priceEl?.getAttribute('data-clk-listing-item-wholesale-price'),
        text: priceEl?.textContent?.trim().substring(0, 50)
      });
    }

    // Also search globally
    const allPriceEls = document.querySelectorAll('[data-testid="wholesalePrice-new"], [data-test="wholesalePrice-new"]');
    console.log(`Found ${allPriceEls.length} price elements globally`);

    return {sku, strategies, totalPriceElements: allPriceEls.length };
  });

  console.log('\n=== RESULTS ===');
  console.log(JSON.stringify(result, null, 2));

  await page.waitForTimeout(5000);
  await browser.close();
})().catch(console.error);
