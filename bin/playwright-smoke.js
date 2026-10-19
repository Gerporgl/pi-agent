// Build-time smoke test for the Playwright install: launches both preinstalled
// browsers headlessly as a non-root user and renders text. Also serves as the
// smallest possible example of the library API.
const { chromium, firefox } = require("playwright");

const browsers = [chromium, firefox];

(async () => {
  for (const browserType of browsers) {
    const browser = await browserType.launch();
    const page = await (await browser.newContext()).newPage();
    await page.setContent("<h1>ok</h1>");
    const text = await page.locator("h1").textContent();
    if (text !== "ok") throw new Error(`${browserType.name()}: rendered "${text}"`);
    await page.screenshot({ path: `/tmp/playwright-smoke-${browserType.name()}.png` });
    console.log(`${browserType.name()} ${browser.version()} ok`);
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
