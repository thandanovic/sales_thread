/**
 * Login Flow Test Script
 *
 * Tests the login flow with actual credentials to verify:
 * - Login form detection
 * - Credential submission
 * - Success/error handling
 * - Session persistence
 * - Cloudflare bypass with stealth mode
 * - Two-step SSO authentication
 */

const { chromium } = require('playwright-extra');
const stealth = require('puppeteer-extra-plugin-stealth');
const fs = require('fs');
require('dotenv').config();

// Add stealth plugin to avoid detection
chromium.use(stealth());

const SITE_URL = 'https://ba.e-cat.intercars.eu/bs/';

async function testLogin() {
  console.log('🔐 Testing Intercars Login Flow (with Stealth Mode)...\n');

  if (!process.env.INTERCARS_USERNAME || !process.env.INTERCARS_PASSWORD) {
    console.error('❌ Error: Please set INTERCARS_USERNAME and INTERCARS_PASSWORD in .env file');
    console.log('   Copy .env.example to .env and fill in your credentials\n');
    return;
  }

  const browser = await chromium.launch({
    headless: false, // Run in headed mode to better bypass Cloudflare
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

  try {
    // Step 1: Navigate to site and handle SSO login
    console.log('📄 Step 1: Navigating to site...');
    await page.goto(SITE_URL, { waitUntil: 'domcontentloaded', timeout: 30000 });
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

        await page.screenshot({ path: 'scraper/screenshots/02-email-entered.png' });

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

        await page.screenshot({ path: 'scraper/screenshots/03-password-entered.png' });

        // Submit password form
        const signInButton = page.locator('button[type="submit"], input[type="submit"]').first();
        if (await signInButton.count() > 0) {
          await signInButton.click();
          console.log('   ✓ Sign in button clicked\n');

          await page.waitForTimeout(3000);
          await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});

          console.log(`   ✓ After login URL: ${page.url()}\n`);
          await page.screenshot({ path: 'scraper/screenshots/04-after-login.png', fullPage: true });
        }
      } else {
        console.log('   ⚠️  Password field not found - may still be on email step or login failed');
        await page.screenshot({ path: 'scraper/screenshots/login-stuck.png', fullPage: true });
        return;
      }
    }

    // Step 2: Check if login was successful
    console.log('✅ Step 2: Checking login result...');

    const currentUrl = page.url();
    const stillOnLogin = currentUrl.includes('login') || currentUrl.includes('auth');

    if (!stillOnLogin) {
      console.log('   ✅ Login appears SUCCESSFUL!');
      console.log(`   Current URL: ${currentUrl}`);

      // Save cookies for future use
      const cookies = await context.cookies();
      fs.writeFileSync('scraper/data/session-cookies.json', JSON.stringify(cookies, null, 2));
      console.log('   💾 Session cookies saved to: data/session-cookies.json');

      // Extract some logged-in state info
      console.log('\n📊 Logged-in page analysis:');
      const info = await page.evaluate(() => {
        return {
          title: document.title,
          hasUserMenu: !!document.querySelector('[class*="user"], [class*="account"], [class*="profile"]'),
          mainSections: Array.from(document.querySelectorAll('nav a, .nav a, [role="navigation"] a'))
            .slice(0, 10)
            .map(a => ({ text: a.textContent?.trim(), href: a.getAttribute('href') }))
            .filter(item => item.text)
        };
      });

      console.log(`   Page title: ${info.title}`);
      console.log(`   User menu detected: ${info.hasUserMenu}`);
      console.log('   Navigation items:');
      info.mainSections.forEach(item => {
        console.log(`     - ${item.text}: ${item.href}`);
      });

    } else {
      console.log('   ⚠️  Login status UNCLEAR - still on login page');
      await page.screenshot({ path: 'scraper/screenshots/login-unclear.png', fullPage: true });
    }

  } catch (error) {
    console.error('\n❌ Error during login test:', error.message);
    await page.screenshot({ path: 'scraper/screenshots/error-login.png' });
  } finally {
    await browser.close();
    console.log('\n🏁 Login test complete!\n');
  }
}

testLogin().catch(console.error);
