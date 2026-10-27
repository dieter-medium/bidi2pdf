---
name: render-pdf
description: This skill should be used when a web page, a URL or an HTML file has to become a PDF with bidi2pdf's command line, including a PDF of a page's screen view, dark mode or mobile layout, a tagged (accessible) PDF, or a PDF piped through stdin/stdout. Covers the order of commands, the waits, reading the JSON result and the exit codes.
---

# Render a PDF with the bidi2pdf CLI

bidi2pdf prints a page in a real Chrome over WebDriver BiDi. This skill is the order of work and the
pitfalls; the exact options are in `bidi2pdf help render`, the exact result shape in
`bidi2pdf schema render`. Read those instead of guessing an option.

**Does not:** scrape page content or automate a site (log in, click through). bidi2pdf is a
renderer; for a page that needs steps before printing, write a recipe (the `pdf-recipe` skill).

## Ground rules

- **bidi2pdf is the renderer.** If it fails, report its `error.code`, `error.hint` and exit code;
  never make the PDF or screenshot another way (Chrome's own print-to-PDF, another PDF engine).
- **Install nothing unasked.** Name what is missing and suggest a way (the `render-pdf` skill's
  preflight); run nothing that changes the system without the user's yes.
- **bidi2pdf's results first.** Read its `--json` result instead of inspecting the PDF with other
  tools.

## 1. Preflight

```bash
bidi2pdf version --json
```

One call answers three questions: is bidi2pdf there at all, which version (`bidi2pdf`), and whether
`pages` will be filled (`pdf_reader` is `null` without that gem). `--media`, `--color_scheme` and
`--reduced_motion`, and a clean stdout for `--json` and `--output -`, need 0.1.23 or later. If
`bidi2pdf help render` does not list an option, the installed gem is older - say so instead of
working around it.

**When bidi2pdf is missing**, look first, install nothing yet, and suggest the lightest way that fits:

```bash
ruby -v; docker info --format '{{.ServerVersion}}'; command -v chromium chromium-browser google-chrome
```

1. **Docker answers** (`docker info` prints a server version, not an error - an installed client
   without a reachable daemon or socket permission does not count): nothing to install, the image
   has Ruby, Chromium and pdf-reader. Inside a container that uses the host's Docker, `-v` mounts
   a path of the host, not of the container.
2. **Ruby 3.4 or later is there:** `gem install bidi2pdf`, plus a browser if none was found.
   `pdf-reader` only when the page count is needed.
3. **No Ruby, or an older one:** a distribution's Ruby is too old (Debian 12 ships 3.1, Debian 13
   3.3, Ubuntu 24.04 3.2 - and a `node` image is Debian). Homebrew's `ruby` on macOS, a version
   manager (`mise`, `rbenv`) elsewhere - or option 1, which needs no Ruby at all.

```bash
# 1. Docker: no install
docker run --rm -v "$PWD:/reports" dieters877565/bidi2pdf:main-slim \
  bidi2pdf render --url https://example.com --output /reports/example.pdf --json
# 2. Ruby 3.4+
gem install bidi2pdf
gem install pdf-reader    # optional: fills "pages"
# Browser on Debian, or in a Debian-based container (the packaged driver also works on ARM)
sudo apt-get install -y chromium chromium-driver
# Ruby on macOS (Google Chrome, if installed, is the browser)
brew install ruby
```

bidi2pdf fetches a matching chromedriver itself, which may fail on ARM Linux - there use the
packaged `chromium-driver`. Ubuntu's `chromium` is a snap that does not run in a container: use a
shared browser there (the `remote-chrome` skill).

**Show the user the commands that fit and run them only after a yes** - they change the system.

Where Chrome runs:

- **A shared browser** (a chromedriver container): pass `--remote-browser-url
  http://<host>:3000/session` to every command. The `remote-chrome` skill sets one up.
- **Local**: bidi2pdf starts chromedriver itself; Chrome or Chromium must be installed. Inside a
  container add `--no-sandbox` (or set `DISABLE_CHROME_SANDBOX=true`).

## 2. Render

```bash
bidi2pdf render --url https://example.com/invoice/123 --output invoice.pdf \
  --wait-network-idle --json --manifest invoice.manifest.json
```

- **Waits.** Without one, bidi2pdf prints as soon as the page's load event fired.
  `--wait-network-idle` waits for late requests (lazy images, fetched data).
  `--wait-window-loaded` waits until the page's **own script** sets `window.loaded = true` - use it
  for Paged.js or any page that finishes rendering itself, never for a page that does not set it:
  that one waits the whole `--default-timeout` (60 s) and fails with `COMMAND_TIMEOUT`.
- **Input.** `--url`, `--html-file`, or `--stdin` for HTML on standard input - exactly one.
- **Output.** `--output file.pdf`; `--output -` writes the PDF bytes to stdout and nothing else (it
  cannot be combined with `--json`).
- **`--manifest`** records what was rendered with which options, to reproduce or debug it later
  (cookie values and secret headers are left out).
- **Cookies, headers, basic auth:** `--cookie name=value`, `--header Name=value`, `--auth user:pass`.

```bash
cat page.html | bidi2pdf render --stdin --output - > page.pdf
```

## 3. Page size, margins, screen view, mobile layout

All sizes are **centimetres**: `--page-width`/`--page-height` (default US Letter, 21.59 x 27.94),
`--margin-top/-bottom/-left/-right`. Chrome's own default margin is 1 cm a side.

By default Chrome prints with the page's **print stylesheet**. To print what the screen shows:

```bash
bidi2pdf render --url https://example.com --output screen.pdf --media screen
bidi2pdf render --url https://example.com --output dark.pdf --media screen --color_scheme dark
```

A **mobile layout** needs a narrow page. A printed page is laid out between its side margins, at
96 / 2.54 = about 37.8 CSS px per cm, so set the side margins yourself:

```bash
bidi2pdf render --url https://example.com --output phone.pdf --media screen \
  --page-width 9.525 --page-height 20 --margin-left 0 --margin-right 0
```

9.525 cm without side margins is 360 px; 8.467 cm is 320 px. With Chrome's default 1 cm margins a
9.5 cm page is only about 283 px wide and may hit a smaller breakpoint than intended.

For an accessible PDF add `--generate-tagged-pdf` (and `--generate-document-outline` for bookmarks).

## 4. Read the result, not the logs

With `--json`, stdout carries exactly one JSON document; logs go to stderr. Check `ok`, then:

- `pages`, `bytes`, `sha256` of the PDF. `pages` is `null` without `pdf-reader`, with a warning:
  report it that way, or ask before installing that gem - no other PDF tool for a page count.
- `navigation.final_url` - a redirect to a login page answers 200 and prints perfectly. (A status
  of 400 or more fails the render instead.)
- `network_failures` and `console` even when `ok` is true: a missing image still gives a PDF.
- On failure `error.code`, `error.retryable` and `error.hint`. Retry only when `retryable` is true.

The exit code says the same without parsing:

| Code | Exit | Meaning |
|---|---|---|
| `INVALID_PRINT_OPTION` | 2 | an option value bidi2pdf refuses - fix the command |
| `MISSING_INPUT` | 2 | none of --url, --html-file, --stdin given |
| `DNS_ERROR` | 3 | the host does not resolve **from the browser's machine** |
| `NAVIGATION_TIMEOUT` | 3 | the page did not load in time |
| `NAVIGATION_NOT_FOUND` | 3 | the URL answered 404 |
| `NAVIGATION_FAILED` | 3 | the URL answered another 4xx/5xx, or the connection failed |
| `BROWSER_LAUNCH_FAILED` | 3 | no Chrome/chromedriver - see section 1 |
| `COMMAND_TIMEOUT` | 3 | a wait never finished (often `--wait-window-loaded`) |
| `PDF_GENERATION_FAILED` | 6 | Chrome could not print |
| `OUTPUT_WRITE_FAILED` | 6 | the output path cannot be written |

The full list: `bidi2pdf schema render` (the `error` object) and README "Exit codes".

`--json-stream` writes one progress event per line to stderr while it runs (`bidi2pdf schema
event`), for a long render a user should see move.

## 5. When it fails or looks wrong

Only then, with the same options as the render:

```bash
bidi2pdf diagnose --url https://example.com/invoice/123 --json --screenshot seen.png
```

`diagnose` loads the page like `render` and prints no PDF; `console`, `network_failures`,
`fonts.status`, `print_media` and `paged_js` usually name the cause. The checklist: the
`diagnose-pdf` skill.
