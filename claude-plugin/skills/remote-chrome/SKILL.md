---
name: remote-chrome
description: This skill should be used when bidi2pdf (or bidi2pdf-rails) should render in a shared Chrome container instead of a local browser - setting up the chromedriver container with Docker Compose, connecting to it, sizing it, keeping sessions from piling up, and printing HTML that nobody vouches for. Also when renders fail with "session not created", hang, or the container eats memory.
---

# Run a shared Chrome for bidi2pdf

bidi2pdf talks to chromedriver over HTTP and WebDriver BiDi. A chromedriver container that several
processes share is cheaper and more predictable than a browser per process, and keeps Chrome out of
the application's own container.

**Does not:** cover Kubernetes or a cloud browser service, and does not make an untrusted page safe
on its own (section 5 is what it takes).

## 1. The container

`references/compose.remote-chrome.yml` is a working Compose service, taken from an application that
runs it in development and production. The parts that matter, and why:

- **Image** `dieters877565/chromedriver` (chromedriver + Chromium, hyphenation dictionaries
  included). It answers on port 3000; the new-session URL is `http://<service>:3000/session`.
- **No published port, an internal network only.** Whoever reaches port 3000 drives a browser: keep
  it to the containers that render. No VNC (`ENABLE_VNC: "false"`).
- **Chrome's sandbox:** either `cap_add: [SYS_ADMIN]`, or no extra capability and every client passes
  `--no-sandbox` (`DISABLE_CHROME_SANDBOX=true` for the CLI). Some CI runners drop `--cap-add`
  silently - there only `--no-sandbox` works.
- **Limits from measurement, not guesses:** one Chrome session runs ~110 threads (Docker counts them
  as pids) and a few hundred MB. `pids_limit: 1024`, `mem_limit: 2g` with `memswap_limit` equal (no
  swap: a Chrome out of memory is killed and replaced instead of freezing every render),
  `shm_size: 256m`. At 512 pids and 1 GB, four concurrent renders crashed or froze it.
- **`WATCHDOG_ENABLED: "true"`** stops chromedriver when it stops answering or memory thrashes;
  `restart: unless-stopped` then starts a fresh container. The image's health check (`/status`)
  only marks it unhealthy - Docker never restarts an unhealthy container by itself.
- **`LANG`/`LANGUAGE`** set the browser's locale: date and number formats in form fields follow it.

In CI, wait for the container to be healthy before the first render; "Connection refused" on port
3000 right after start means it was not ready yet.

## 2. Connect

```bash
bidi2pdf render --url http://app:3000/report --output report.pdf \
  --remote-browser-url http://remote-chrome:3000/session
```

The page URL must be reachable **from the browser container**, not from where the command runs:
`localhost` there is the browser itself. Use the application's service name, and for a Rails app
make the PDF's asset host that same name, or every stylesheet fails and the PDF is blank.

## 3. Keep sessions from piling up

A process that crashes or is killed mid-render leaves its Chrome session open on the shared
chromedriver, and each one holds memory. bidi2pdf records the sessions it opens on this machine
(`SessionRegistry`); look and clean up with:

```bash
bidi2pdf sessions --remote-browser-url http://remote-chrome:3000/session
bidi2pdf sweep --remote-browser-url http://remote-chrome:3000/session --dry-run
bidi2pdf sweep --remote-browser-url http://remote-chrome:3000/session
```

`sweep` closes recorded sessions older than `--older-than` (600 s), unresponsive ones, and the oldest
above `--max-sessions`; never one younger than `--min-age` or one a running process holds. Leave
`--scope all` to a chromedriver your application owns alone - it also closes sessions other
programs opened. Run `sweep` from cron or a timer, and `--dry-run` first.

Code that opens its own sessions (a test driver, a script) passes a `SessionRegistry` to
`Bidi2pdf::Bidi::Session.new(..., registry: Bidi2pdf::SessionRegistry.new(url))` and closes the
session in an `ensure`, with a time limit on the close: a hung close is the most common leak.

## 4. Size it

Renders run in parallel on one chromedriver, one session (or a tab of one) each. Measure your own
pages: start with 2 GB, run the peak number of renders at once, and watch `docker stats` for memory
and pids. Raise `mem_limit` and `pids_limit` together.

## 5. Printing HTML nobody vouches for

A page from a user is a page that runs its scripts in your browser. Before navigating:

- `tab.disable_script_execution` - the page's JavaScript does not run at all.
- Give the browser container **no direct internet access**: route it through an egress proxy that
  refuses private and internal addresses, so a page cannot make the browser fetch your internal
  services. Never put it on the same network as your database.
- Prefer printing HTML you built (`render_html_content`, `--html-file`) over handing Chrome a URL a
  user typed.
