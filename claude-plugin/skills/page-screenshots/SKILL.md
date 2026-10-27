---
name: page-screenshots
description: This skill should be used when pages of a web site or app need screenshots for a design, UX or accessibility review - at phone and desktop width, in light and dark mode - or when one screenshot shows what Chrome rendered for a PDF. Uses bidi2pdf's browser (local or a shared chromedriver), not Playwright or Puppeteer.
---

# Screenshots for review with bidi2pdf

A reviewer, human or agent, judges a page from what Chrome draws. Shoot every page that changed at
phone width first, then desktop, each in light and dark mode, and hand over the files with the
page and the width in their names.

**Does not:** compare screenshots against a baseline or judge them - it produces them. For a
visual regression check, diff the PNGs in your own test (bidi2pdf's `contains_pdf_image` compares
images inside a PDF, see `pdf-specs`).

## Ground rules

- **bidi2pdf is the renderer.** When it fails, never make the PDF or screenshot another way (Chrome's
  own print-to-PDF, wkhtmltopdf, a browser script of your own): report its `error.code`, `error.hint`
  and exit code, then fix the cause or ask.
- **Install nothing unasked.** If bidi2pdf, Ruby 3.4+ or Chrome is missing, say which and offer the
  ways: `gem install bidi2pdf` where Ruby is there, the image `dieters877565/bidi2pdf:main-slim`
  (Chromium and pdf-reader included), or a shared browser (the `remote-chrome` skill); the
  `render-pdf` skill's preflight has the commands. No system packages without the user's go-ahead.
- **Use bidi2pdf's own results.** Pages, size and checksum are in the `--json` result (`pages`,
  `bytes`, `sha256`). `pages` is `null` without the `pdf-reader` gem: say so, or ask to install that
  gem - never other PDF tools.
- **Diagnose only what went wrong.** `bidi2pdf diagnose` is for a render that failed or looks wrong,
  not a step before every render.

## 1. One shot

```bash
bidi2pdf diagnose --url http://app:4000/pricing --screenshot pricing.png --media screen --color_scheme dark
```

The shot is the whole document at the browser's default viewport. Good for "what did Chrome see";
for review sets with fixed widths use the script below.

## 2. A review set

```bash
SKILL_DIR=/absolute/path/to/skills/page-screenshots
ruby "$SKILL_DIR/scripts/screenshots.rb" --base http://app:4000 --pages /,/pricing,/signup \
  --widths 360,1280 --out tmp/screenshots --remote-browser-url http://remote-chrome:3000/session
```

Set `SKILL_DIR` first, to the absolute path of this skill's own folder - the folder of this SKILL.md, which the
agent (Claude Code, Codex) names when it loads the skill. Nothing guarantees that the variable is already set:
without it, the command looks for `/scripts/screenshots.rb`. In a checkout of bidi2pdf it is
`"$PWD/claude-plugin/skills/page-screenshots"`. Run the script by that path, not relative to the project you are
shooting.

It writes one PNG for every page, width and colour scheme and prints each path:
`<page path>-<width>-<scheme>.png`, with the page's folders kept (`/account/settings` becomes
`account/settings-360-light.png`, `/` becomes `index-...`). When a page's path holds characters a file
name should not, or a query, the name gets a short hash of the path, so no two pages overwrite each
other. It sets the viewport, emulates `prefers-color-scheme`
with `media: screen`, waits for the network to go quiet and captures the full page. Without
`--remote-browser-url` it starts a local chromedriver. It needs the bidi2pdf release with
`BrowserTab#emulate_media` (0.1.23 or later).

- **360 px first.** Most layout bugs show at the narrow width; 1280 covers desktop. Add the site's own
  breakpoints when they matter (e.g. 768).
- **The base URL is seen from the browser.** A shared browser in a container cannot reach
  `localhost` on your machine - use a name it resolves.
- A page that needs a login: open it in the Ruby API with a cookie (`tab.set_cookie`) before
  navigating, or shoot a page that does not need one.

## 3. From Ruby

The same steps for your own test or tool:

```ruby
tab.emulate_media(media: "screen", color_scheme: "dark")
tab.set_viewport(width: 360, height: 900)
tab.navigate_to("http://app:4000/pricing")
tab.wait_until_network_idle
tab.screenshot("tmp/pricing-360-dark.png")
```

`screenshot(origin: "viewport")` captures exactly the viewport instead of the whole page. A
page that toggles dark mode by a class or `data-theme` instead of `prefers-color-scheme` needs that
attribute set (`tab.execute_script(...)`) - emulation changes only the media feature.

## 4. Hand-over

List the files with page, width and scheme, and say what the reviewer should look at (the changed
part). Reviewers need both widths and both schemes; a dark-mode contrast bug never shows in a light
screenshot.
