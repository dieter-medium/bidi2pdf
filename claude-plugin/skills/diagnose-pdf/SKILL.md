---
name: diagnose-pdf
description: This skill should be used when a PDF made with bidi2pdf (CLI, Ruby API or bidi2pdf-rails) is blank, half empty, unstyled, missing images or fonts, cut off, on the wrong number of pages, shows dates in the wrong format, or breaks words badly. A checklist from the cheapest check to the most expensive, using bidi2pdf diagnose.
---

# Find out why a PDF looks wrong

Start with what Chrome reports, not with the page's code. Each check below names what to look at
and the usual cause.

**Does not:** fix the page's design or CSS for you - it finds why the PDF differs from what was
expected, then the fix belongs in the page or the render call.

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

## 1. Ask Chrome

```bash
bidi2pdf diagnose --url https://example.com/report --json --screenshot seen.png --pdf try.pdf
```

Use the same `--remote-browser-url`, cookies, headers and waits as the real render: a diagnosis of a
different request explains nothing. Read the JSON in this order.

## 2. The checklist

1. **`network_failures`** - every stylesheet, font, image or script the browser could not load.
   The most common cause of a blank or unstyled PDF: the address works from your machine but not
   **from the browser's**. A browser in a container resolves names in its own network; `localhost`
   there is the container itself. Use an address the browser can reach (for a Rails app, the asset
   host the browser sees - bidi2pdf-rails' asset-host setting), then diagnose again.
2. **`console`** - a script error can stop the page before it renders its content.
3. **`page.url` / `navigation.final_url`** - a redirect to a login page answers 200 and prints
   perfectly; the right cookies or headers are missing. (A 4xx/5xx answer fails the render with
   `NAVIGATION_NOT_FOUND` or `NAVIGATION_FAILED` instead.)
4. **`fonts.status`** - `loading` or entries in `fonts.failed`: the PDF falls back to another font
   or shows boxes. Add a wait (`--wait-network-idle`), or fix the font URL (see 1).
5. **`print_media`** - the page's `@media print` rules and `@page` rules. A print stylesheet that
   hides content, `fixed_or_sticky_elements` repeated on every page, or a `@page` size that fights
   `--page-width`. To print what the screen shows instead: `--media screen`.
6. **`paged_js`** - `detected: true` but `ready: false`: Paged.js had not finished. Render with
   `--wait-window-loaded` and let the page set `window.loaded = true` when Paged.js is done; without
   that flag the wait runs into `--default-timeout`.
7. **Late content** (charts, lazy images): `--wait-network-idle`, or a recipe with `wait_for`
   (`selector:` of the last thing that appears).
8. **Page count or cut-off content** - page size and margins are in **cm**; Chrome's own default
   margin is 1 cm a side. A layout breakpoint follows the width **between the side margins**, not
   the paper's (96 / 2.54 CSS px per cm).
9. **Dates and number formats** in form fields come from the browser's locale, not the page: set
   `LANG`/`LANGUAGE` on the browser's container (e.g. `de_DE.UTF-8`).
10. **Hyphenation** (`hyphens: auto` does nothing, or breaks anywhere): the browser needs Chrome's
    hyphenation dictionaries installed for the page's `lang`. bidi2pdf's chromedriver image ships
    them; a self-built image may not. The page needs a correct `lang` attribute.

## 3. When the log is needed

`render ... --log-network-traffic --log-level debug` logs every request with its timing.
`--network-log-format pdf` writes that log as its own PDF next to the output. Use it only when the
JSON above did not explain the problem; it is long.
