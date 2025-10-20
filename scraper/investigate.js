/**
 * Intercars Site Investigation Script
 *
 * This script explores the Intercars e-catalog site to understand:
 * - Login flow and form selectors
 * - Main page structure
 * - Product listing layout
 * - Product detail page structure
 * - Data extraction points
 */

const { chromium } = require('playwright');
require('dotenv').config();

const SITE_URL = 'https://ba.e-cat.intercars.eu/bs/';

async function investigate() {
  console.log('🔍 Starting Intercars site investigation...\n');

  const browser = await chromium.launch({
    headless: process.env.HEADLESS === 'true',
    slowMo: parseInt(process.env.SLOW_MO) || 100
  });

  const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
  });

  const page = await context.newPage();

  try {
    // Step 1: Navigate to main page
    console.log('📄 Step 1: Loading main page...');
    await page.goto(SITE_URL, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(2000);

    const title = await page.title();
    console.log(`   Page title: ${title}`);
    console.log(`   Current URL: ${page.url()}\n`);

    // Check if we're redirected to login
    const currentUrl = page.url();
    const isLoginPage = currentUrl.includes('login') || currentUrl.includes('auth');

    if (isLoginPage) {
      console.log('🔐 Detected LOGIN PAGE\n');
      await investigateLoginPage(page);
    } else {
      console.log('🏠 Detected MAIN/CATALOG PAGE\n');
      await investigateMainPage(page);
    }

    // Step 2: Take screenshots
    console.log('📸 Taking screenshots...');
    await page.screenshot({
      path: 'scraper/screenshots/01-initial-page.png',
      fullPage: true
    });
    console.log('   Saved: screenshots/01-initial-page.png\n');

    // Step 3: Analyze page structure
    console.log('🏗️  Step 3: Analyzing page structure...');
    await analyzePage(page);

  } catch (error) {
    console.error('❌ Error during investigation:', error.message);
    await page.screenshot({ path: 'scraper/screenshots/error.png' });
  } finally {
    await browser.close();
    console.log('\n✅ Investigation complete!');
  }
}

async function investigateLoginPage(page) {
  console.log('   Analyzing login form...\n');

  // Find all forms
  const forms = await page.$$('form');
  console.log(`   Found ${forms.length} form(s)\n`);

  for (let i = 0; i < forms.length; i++) {
    console.log(`   === Form #${i + 1} ===`);
    const form = forms[i];

    // Get form attributes
    const action = await form.getAttribute('action');
    const method = await form.getAttribute('method');
    const formClass = await form.getAttribute('class');
    const formId = await form.getAttribute('id');

    console.log(`   Action: ${action || 'N/A'}`);
    console.log(`   Method: ${method || 'N/A'}`);
    console.log(`   Class: ${formClass || 'N/A'}`);
    console.log(`   ID: ${formId || 'N/A'}`);

    // Find input fields
    const inputs = await form.$$('input');
    console.log(`   Inputs: ${inputs.length}`);

    for (const input of inputs) {
      const type = await input.getAttribute('type');
      const name = await input.getAttribute('name');
      const id = await input.getAttribute('id');
      const placeholder = await input.getAttribute('placeholder');
      const inputClass = await input.getAttribute('class');

      console.log(`     - Type: ${type}, Name: ${name}, ID: ${id}, Placeholder: ${placeholder}`);
      console.log(`       Selector options: #${id}, input[name="${name}"], .${inputClass}`);
    }

    // Find buttons
    const buttons = await form.$$('button');
    console.log(`   Buttons: ${buttons.length}`);

    for (const button of buttons) {
      const type = await button.getAttribute('type');
      const text = await button.textContent();
      const buttonClass = await button.getAttribute('class');
      console.log(`     - Type: ${type}, Text: "${text?.trim()}", Class: ${buttonClass}`);
    }

    console.log('');
  }
}

async function investigateMainPage(page) {
  console.log('   Analyzing catalog structure...\n');

  // Look for navigation, categories, product listings
  const links = await page.$$('a');
  console.log(`   Total links: ${links.length}`);

  // Look for common product listing patterns
  const productSelectors = [
    '.product-card',
    '.product-item',
    '.product',
    '[class*="product"]',
    '[data-product]',
    'article'
  ];

  for (const selector of productSelectors) {
    try {
      const count = await page.locator(selector).count();
      if (count > 0) {
        console.log(`   Found ${count} elements with selector: ${selector}`);
      }
    } catch (e) {
      // Ignore
    }
  }
}

async function analyzePage(page) {
  // Get page structure info
  const structure = await page.evaluate(() => {
    const info = {
      forms: [],
      links: { total: 0, withHref: 0 },
      images: 0,
      headings: {},
      bodyClasses: document.body.className,
      bodyId: document.body.id
    };

    // Analyze forms
    document.querySelectorAll('form').forEach(form => {
      const formInfo = {
        action: form.action,
        method: form.method,
        inputs: []
      };

      form.querySelectorAll('input').forEach(input => {
        formInfo.inputs.push({
          type: input.type,
          name: input.name,
          id: input.id
        });
      });

      info.forms.push(formInfo);
    });

    // Count links
    info.links.total = document.querySelectorAll('a').length;
    info.links.withHref = document.querySelectorAll('a[href]').length;

    // Count images
    info.images = document.querySelectorAll('img').length;

    // Get headings
    ['h1', 'h2', 'h3'].forEach(tag => {
      const elements = document.querySelectorAll(tag);
      if (elements.length > 0) {
        info.headings[tag] = Array.from(elements).map(el => el.textContent.trim()).slice(0, 5);
      }
    });

    return info;
  });

  console.log('   Page Structure:');
  console.log(`   - Forms: ${structure.forms.length}`);
  console.log(`   - Links: ${structure.links.total} (${structure.links.withHref} with href)`);
  console.log(`   - Images: ${structure.images}`);
  console.log(`   - Body classes: ${structure.bodyClasses || 'none'}`);
  console.log(`   - Body ID: ${structure.bodyId || 'none'}`);

  if (structure.headings.h1) {
    console.log(`   - H1 headings: ${structure.headings.h1.join(', ')}`);
  }

  console.log('\n   Detailed form info:');
  structure.forms.forEach((form, i) => {
    console.log(`   Form ${i + 1}:`);
    console.log(`     Action: ${form.action}`);
    console.log(`     Method: ${form.method}`);
    console.log(`     Inputs: ${form.inputs.map(inp => `${inp.type}[${inp.name}]`).join(', ')}`);
  });
}

// Run investigation
investigate().catch(console.error);
