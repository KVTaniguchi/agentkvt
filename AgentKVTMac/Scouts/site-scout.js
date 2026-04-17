const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

/**
 * SiteScout: A Playwright-based browser automation helper for AgentKVT.
 * Reads JSON from stdin and performs actions on a website.
 */
async function run() {
    let input;
    try {
        const rawInput = fs.readFileSync(0, 'utf-8');
        input = JSON.parse(rawInput);
    } catch (e) {
        console.error(JSON.stringify({ status: 'error', message: 'Failed to parse JSON input from stdin: ' + e.message }));
        process.exit(1);
    }

    const { url, actions, storageStatePath, viewport, timeout = 30000 } = input;

    if (!url) {
        console.error(JSON.stringify({ status: 'error', message: 'URL is required' }));
        process.exit(1);
    }

    const browser = await chromium.launch({ 
        headless: true,
        args: ['--disable-blink-features=AutomationControlled'] // Basic stealth
    });
    
    const contextOptions = {
        viewport: viewport || { width: 1280, height: 720 },
        userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
        deviceScaleFactor: 1,
    };

    if (storageStatePath && fs.existsSync(storageStatePath)) {
        contextOptions.storageState = storageStatePath;
    }

    const context = await browser.newContext(contextOptions);
    
    // Add realistic headers and masking
    await context.addInitScript(() => {
        Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
    });

    const page = await context.newPage();
    page.setDefaultTimeout(timeout);

    try {
        // Step 1: Navigate to URL
        await page.goto(url, { waitUntil: 'networkidle' });

        const results = [];
        // Step 2: Execute actions
        if (actions && Array.isArray(actions)) {
            for (const action of actions) {
                switch (action.type) {
                    case 'click':
                        await page.click(action.selector);
                        // Optional sleep after click to allow for transitions
                        await page.waitForTimeout(500);
                        break;
                    case 'fill':
                        await page.fill(action.selector, action.value);
                        break;
                    case 'wait':
                        await page.waitForTimeout(action.waitMs || 1000);
                        break;
                    case 'wait_for_selector':
                        await page.waitForSelector(action.selector);
                        break;
                    case 'press':
                        await page.keyboard.press(action.key);
                        break;
                    case 'extract':
                        const content = await page.textContent(action.selector);
                        results.push({ type: 'extract', selector: action.selector, content: content?.trim() });
                        break;
                    case 'screenshot':
                        const ssPath = action.path || `screenshot-${Date.now()}.png`;
                        await page.screenshot({ path: ssPath, fullPage: action.fullPage || false });
                        results.push({ type: 'screenshot', path: ssPath });
                        break;
                }
            }
        }

        // Step 3: Final state extraction
        const finalUrl = page.url();
        const textContent = await page.evaluate(() => {
            // Remove scripts, styles, and other non-content elements
            const clone = document.body.cloneNode(true);
            const toRemove = clone.querySelectorAll('script, style, nav, footer, iframe');
            toRemove.forEach(el => el.remove());
            return clone.innerText || clone.textContent;
        });

        // Save session if requested
        if (storageStatePath) {
            const dir = path.dirname(storageStatePath);
            if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
            await context.storageState({ path: storageStatePath });
        }

        console.log(JSON.stringify({
            status: 'success',
            finalUrl,
            results,
            textContent: textContent.replace(/\s+/g, ' ').trim().slice(0, 15000)
        }));

    } catch (error) {
        console.log(JSON.stringify({
            status: 'error',
            message: error.message,
            stack: error.stack
        }));
        process.exit(1);
    } finally {
        await browser.close();
    }
}

run();
