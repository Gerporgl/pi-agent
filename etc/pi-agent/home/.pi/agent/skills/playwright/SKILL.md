---
name: playwright
description: Use when a real browser is needed (rendering JavaScript pages, scraping, form filling, screenshots, PDFs, e2e UI tests) — Playwright is installed globally with Firefox and a Chromium headless shell; drive it headlessly, never install browsers or a second Playwright copy.
---

# Playwright (browsers already installed, headless only)

Drive real browsers from bash + node. Everything you need is in the image: do
not install anything for it.

## What is installed

- `playwright` (library) and `@playwright/test` (test runner) as **global npm
  packages** in `/usr/lib/node_modules`; CLI: `playwright`.
- Browsers, preinstalled in one shared system directory
  `/usr/local/share/ms-playwright` (`PLAYWRIGHT_BROWSERS_PATH` is baked into the
  image config, `/etc/environment` and both pi-web units, so it is set in every
  shell and pi session). Contents: **Firefox**, **Chromium headless shell**,
  ffmpeg (video). Those are the only two engines.
- `playwright-link` (`/usr/local/bin/playwright-link`): symlinks the global
  packages into a project's `node_modules` — no download, exact version match.
- Fonts for screenshots (Latin, Cyrillic, CJK, emoji): check with `fc-list`.
- **There is no display server, ever.** Nothing headed is possible here.

Always check the installed version instead of trusting memory — the Playwright
package and the browsers change with every image build:

```bash
playwright --version            # CLI == library version
ls /usr/local/share/ms-playwright   # browser revisions (never hardcode those names)
```

## Hard rules

1. **Never `playwright install`, `npx playwright install`, `install-deps` or
   `--with-deps`.** The browser directory is read-only for you and the browsers
   are already there. An "Executable doesn't exist at
   `/usr/local/share/ms-playwright/…`" error never means "download it": the
   asking Playwright version does not match the browser revisions on disk (a
   second Playwright copy inside the project, or `PLAYWRIGHT_BROWSERS_PATH`
   overridden). Remove that copy and use `playwright-link`.
2. **Never `npm install playwright` / `@playwright/test` in a project** when
   the global one will do: a mismatched version expects browser revisions that
   are not on disk. Run `playwright-link` instead. `npm link playwright` does
   not work here (EPERM: it tries to chmod the read-only global install).
3. Headless only: `headless: false`, `channel: "chrome"` / `"msedge"`, the
   `webkit` engine, `devices["Desktop Safari"]`, and the GUI commands
   (`playwright open|codegen|cr|ff|wk|show-report`) cannot work here.
   `chromium.launch()` with defaults *is* the headless Chromium build.
4. Bound anything that touches the network: `timeout 60 node script.js`.

## Using the library from a script

CommonJS resolves from anywhere (`NODE_PATH=/usr/lib/node_modules` is baked in):

```bash
node -e 'const { chromium } = require("playwright"); /* … */'
```

ESM `import` ignores `NODE_PATH`, so link the global packages into the project
first (idempotent, never overwrites a project's own copy):

```bash
cd /path/to/project
playwright-link                     # node_modules/playwright, node_modules/@playwright/test
```

Minimal end-to-end example (`page.spec.js` style, plain script):

```js
const { chromium, firefox } = require("playwright");

(async () => {
  const browser = await chromium.launch();           // headless shell
  const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const page = await context.newPage();
  page.on("console", (m) => console.log("[console]", m.text()));
  page.on("pageerror", (e) => console.log("[pageerror]", e.message));
  await page.goto("https://example.com", { waitUntil: "domcontentloaded" });
  console.log(await page.title());
  console.log(await page.locator("a").first().textContent());
  await page.screenshot({ path: "shot.png", fullPage: true });
  await browser.close();                             // always close, or the script hangs
})().catch((e) => { console.error(e); process.exit(1); });
```

## One-off CLI (no code)

```bash
playwright screenshot --browser chromium https://example.com shot.png
playwright screenshot --browser firefox  --full-page https://example.com shot.png
playwright pdf https://example.com page.pdf
playwright trace actions trace.zip       # inspect a saved trace headlessly
playwright trace open trace.zip          # extract it (then read the files)
```

## Writing tests

```bash
cd /path/to/project && playwright-link
npx playwright test --reporter=list
npx playwright test tests/login.spec.js --reporter=list
```

`playwright.config.js` — keep to the two installed engines:

```js
import { defineConfig, devices } from "@playwright/test";
export default defineConfig({
  testDir: "./tests",
  reporter: "list",
  projects: [
    { name: "chromium", use: { ...devices["Desktop Chrome"] } },
    { name: "firefox", use: { ...devices["Desktop Firefox"] } },
  ],
});
```

Debug failures with the artifacts the runner writes to `test-results/`
(screenshots, and `trace: "on-first-retry"` traces) — read them with
`playwright trace actions`, not by reopening a browser.

## Looking up the API (do this instead of guessing)

The full API reference ships as TypeScript declarations with the package:

```bash
TYPES=/usr/lib/node_modules/playwright/node_modules/playwright-core/types/types.d.ts
rg -n "goto\(|waitForSelector|expectPoll" $TYPES | head
rg -n -A20 "^  async locator" $TYPES          # signatures + documented options
```

`/usr/lib/node_modules/playwright/types/test.d.ts` is the test-runner side
(`test`, `expect`, fixtures). If a doc/comment there and your memory disagree,
the declarations are right — they match the installed version and browsers.

## Gotchas

- Page structure changes without notice (example.com itself has no `<h1>`
  anymore): select on what you verified in the fetched HTML, not on habit.
- A script that never exits usually means a leaked browser: always
  `await browser.close()`, and prefer `timeout N …`.
- If Chromium fails to start with a sandbox error (nested container / LXC
  without user namespaces), relaunch with `chromium.launch({ chromiumSandbox: false })`.
- `page.goto` on an unreachable host throws — check the error text before
  retrying; this container has its own outbound network, not the host's.
- Downloaded/uploaded files: use `page.waitForEvent("download")` and save into
  the project directory (your home is writable, the browser directory is not).
