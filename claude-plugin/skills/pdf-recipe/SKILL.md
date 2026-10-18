---
name: pdf-recipe
description: This skill should be used when a PDF needs more than one render call - waiting for an element, clicking something open, running a script, switching to screen view or a viewport first - or when a PDF must be checked (page count, text in it, no failed requests). Writes and validates a bidi2pdf recipe YAML without a browser, then runs it.
---

# Write and run a bidi2pdf recipe

A recipe is a rendering contract: the steps a page needs before it is printed, and what the PDF must
be like afterwards. It is not a general automation script. The source of truth for its shape is
`bidi2pdf schema recipe`; read it once before writing one.

**Does not:** log in through forms, follow links across pages, or extract data. One page, prepared
and printed. For a plain page without steps, `render` is enough (the `render-pdf` skill).

## 1. Write it

```yaml
version: 1
source:
  url: https://example.com/invoice/123
actions:
  - wait_for:
      selector: "#invoice"
      timeout: 10
  - click:
      selector: "#show-details"
  - wait_network_idle:
      timeout: 10
assert:
  - selector_exists:
      selector: "#total"
  - no_console_errors: true
  - page_count: 2
  - pdf_text_present:
      text: "Invoice #123"
output:
  pdf: invoice.pdf
  manifest: invoice.manifest.json
```

- **source**: exactly one of `url`, `file`, `stdin`.
- **actions** run in order, **after** the page has loaded:
  - `wait_for` takes exactly one of `selector`, `paged_js: true` (a Paged.js page exists) or `script`
    (a JS expression that becomes truthy), plus an optional `timeout` (default 10 s).
  - `click`, `evaluate` (a script, optionally `assign:` its result), `inject_script`/`inject_style`
    (`content:` or `url:`).
  - `set_viewport` (`width`, `height`, optional `device_pixel_ratio`).
  - `wait_network_idle` (`timeout`).
  - `emulate_media` (`media: screen|print`, `color_scheme: light|dark`, `reduced_motion`) - from the
    release after 0.1.22.
- **assert** runs after printing. Page checks: `selector_exists`, `text_present`,
  `no_console_errors`, `no_network_failures`, `fonts_loaded`. PDF checks: `page_count`,
  `pdf_text_present`, `pdf_not_blank` - these need the `pdf-reader` gem.
- **output** needs at least one of `pdf`, `manifest`, `screenshot`.

Two rules people trip over:

- `no_console_errors`, `no_network_failures`, `fonts_loaded` and `pdf_not_blank` are presence-only:
  write them as `true`. `false` is rejected - leave the assertion out instead.
- `no_network_failures` fails on **any** failed request, a missing favicon or a 404 image included.
  Check `bidi2pdf diagnose --json` first and fix the page, or leave that assertion out.

## 2. Validate without a browser

```bash
bidi2pdf run invoice.yml --validate --json
```

This checks the shape, every action and assertion name and every value, and that `pdf-reader` is
there when a PDF assertion needs it - no browser starts. Iterate until `ok` is true; on failure
`error.details.path` names the step (`assert[0].no_console_errors`).

## 3. Run it

```bash
bidi2pdf run invoice.yml --json --remote-browser-url http://chrome:3000/session
```

The result lists every action and assertion with its own `ok`. A failed step stops the run with
`error.code` `PAGE_NOT_AS_EXPECTED` (or `SELECTOR_NOT_FOUND` for a `wait_for` that never matched),
exit code 4, and `error.details` says which check failed and why (for `no_network_failures` the
failed requests). Exit 2 is a recipe the validator refused; exit 3 is the browser or the page not
loading. `--json-stream` reports progress on stderr while it runs.
