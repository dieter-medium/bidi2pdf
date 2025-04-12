[![Build Status](https://github.com/dieter-medium/bidi2pdf/actions/workflows/ruby.yml/badge.svg)](https://github.com/dieter-medium/bidi2pdf/blob/main/.github/workflows/ruby.yml)
[![Maintainability](https://api.codeclimate.com/v1/badges/6425d9893aa3a9ca243e/maintainability)](https://codeclimate.com/github/dieter-medium/bidi2pdf/maintainability)
[![Gem Version](https://badge.fury.io/rb/bidi2pdf.svg)](https://badge.fury.io/rb/bidi2pdf)
[![Test Coverage](https://api.codeclimate.com/v1/badges/6425d9893aa3a9ca243e/test_coverage)](https://codeclimate.com/github/dieter-medium/bidi2pdf/test_coverage)

---

# 📄 Bidi2pdf – Bulletproof PDF generation via Chrome's BiDi Protocol

**Bidi2pdf** is a powerful Ruby gem that transforms modern web pages into high-fidelity PDFs using Chrome’s
**BiDirectional (BiDi)** protocol. Whether you're automating reports, archiving websites, or shipping documentation,
Bidi2pdf gives you **precision, flexibility, and full control**.

---

## ✨ Key Features

✅ **One-liner CLI** – From URL to PDF in a single command  
✅ **Full customization** – Inject cookies, headers, auth credentials  
✅ **Smart waiting** – Wait for complete page load or network idle  
✅ **Headless support** – Run quietly in the background  
✅ **Docker-ready** – Plug and play with containers  
✅ **Modern architecture** – Built on Chrome's next-gen BiDi protocol  
✅ **Network logging** – Know which requests fail during rendering  
✅ **Console log capture** – See what goes wrong inside the browser

---

## 🚀 Installation

### Bundler

```ruby
gem 'bidi2pdf'
```

### Standalone

```bash
gem install bidi2pdf
```

### Requirements

- **Ruby** ≥ 3.3
- **Chrome/Chromium**
- Automatic ChromeDriver management via [chromedriver-binary](https://github.com/dieter-medium/chromedriver-binary)

---

## ⚙️ Basic Usage

### Command-line

```bash
bidi2pdf render --url https://example.com --output example.pdf
```

### Advanced CLI Options

```bash
bidi2pdf render \
  --url https://example.com \
  --output example.pdf \
  --cookie session=abc123 \
  --header X-API-KEY=token \
  --auth admin:password \
  --wait_network_idle \
  --wait_window_loaded \
  --log-level debug
```

---

## 🧠 Programmatic API

### Classic Approach

```ruby
require 'bidi2pdf'

launcher = Bidi2pdf::Launcher.new(
  url: 'https://example.com',
  output: 'example.pdf',
  cookies: { 'session' => 'abc123' },
  headers: { 'X-API-KEY' => 'token' },
  auth: { username: 'admin', password: 'password' },
  wait_window_loaded: true,
  wait_network_idle: true
)

launcher.launch
```

### DSL – Quick & Clean

```ruby
require "bidi2pdf"

Bidi2pdf::DSL.with_tab(headless: true) do |tab|
  tab.navigate_to("https://example.com")
  tab.wait_until_network_idle
  tab.print("example.pdf")
end
```

---

## 🧬 Deep Integration Example

Get fine-grained control using Chrome sessions, tabs, and BiDi commands:

<details>
<summary>🔍 Show full example</summary>

```ruby
require "bidi2pdf"

# 1. Remote or local session?
session = Bidi2pdf::Bidi::Session.new(
  session_url: "http://localhost:9092/session",
  headless: true,
)

# Alternative: local session via ChromeDriver
# manager = Bidi2pdf::ChromedriverManager.new(headless: false)
# manager.start
# session = manager.session

session.start
session.client.on_close { puts "WebSocket session closed" }

# 2. Create browser/tab
browser = session.browser
context = browser.create_user_context
window = context.create_browser_window
tab = window.create_browser_tab

# 3. Inject configuration
tab.set_cookie(name: "auth", value: "secret", domain: "example.com", secure: true)
tab.add_headers(url_patterns: [{ type: "pattern", protocol: "https", hostname: "example.com", port: "443" }],
                headers: [{ name: "X-API-KEY", value: "12345678" }])
tab.basic_auth(url_patterns: [{ type: "pattern", protocol: "https", hostname: "example.com", port: "443" }],
               username: "username", password: "secret")

# 4. Render PDF
tab.navigate_to "https://example.com"

# Alternative: send html code to the browser
# tab.render_html_content("<html>...</html>")

tab.wait_until_network_idle
tab.print("my.pdf")

# 5. Cleanup
tab.close
window.close
session.close
```

</details>

---

## 🐳 Docker Support

### 🛠️ Build & Run Locally

```bash
# Prepare the environment
rake build

# Build the Docker image
docker build -t bidi2pdf -f docker/Dockerfile .

# Run the container and generate a PDF
docker run -it --rm \
  -v ./output:/reports \
  bidi2pdf \
  bidi2pdf render --url=https://example.com --output /reports/example.pdf

```

### ⚡ Use the Prebuilt Image (Recommended for Fast Start)

Grab it directly from [Docker Hub](https://hub.docker.com/r/dieters877565/bidi2pdf)

```bash
docker run -it --rm \
  -v ./output:/reports \
  dieters877565/bidi2pdf:main-slim \
  bidi2pdf render --url=https://example.com --output /reports/example.pdf
```

✅ Tip: Mount your local directory (e.g. ./output) to /reports in the container to easily access the generated PDFs.

### Docker Compose

```bash
rake build
docker compose -f docker/docker-compose.yml up -d

# simple example
docker compose -f docker/docker-compose.yml exec app bidi2pdf render --url=http://nginx/sample.html --wait_window_loaded --wait_network_idle --output /reports/simple.pdf

# with a local file
docker compose -f docker/docker-compose.yml exec app bidi2pdf render --url=file:///reports/sample.html--wait_network_idle --output /reports/simple.pdf


# basic auth example
docker compose -f docker/docker-compose.yml exec app bidi2pdf render --url=http://nginx/basic/sample.html --auth admin:secret --wait_window_loaded --wait_network_idle --output /reports/basic.pdf

# header example
docker compose -f docker/docker-compose.yml exec app bidi2pdf render --url=http://nginx/header/sample.html --header "X-API-KEY=secret" --wait_window_loaded --wait_network_idle --output /reports/header.pdf

# cookie example
docker compose -f docker/docker-compose.yml exec app bidi2pdf render --url=http://nginx/cookie/sample.html --cookie "auth=secret" --wait_window_loaded --wait_network_idle --output /reports/cookie.pdf

# remote chrome example
docker compose -f docker/docker-compose.yml exec app bidi2pdf render --url=http://nginx/cookie/sample.html --remote_browser_url http://remote-chrome:3000/session --cookie "auth=secret" --wait_window_loaded --wait_network_idle --output /reports/remote.pdf

docker compose -f docker/docker-compose.yml down
```

---

## 🧩 Configuration Options

| Flag                   | Description                                |
|------------------------|--------------------------------------------|
| `--url`                | Target URL (required)                      |
| `--output`             | Output PDF file (default: output.pdf)      |
| `--cookie`             | Set cookie in `name=value` format          |
| `--header`             | Inject custom header `name=value`          |
| `--auth`               | Basic auth as `user:pass`                  |
| `--headless`           | Run Chrome headless (default: true)        |
| `--port`               | ChromeDriver port (0 = auto)               |
| `--wait_window_loaded` | Wait until `window.loaded` is set to true  |
| `--wait_network_idle`  | Wait until network is idle                 |
| `--log_level`          | Log level: debug, info, warn, error, fatal |
| `--remote_browser_url` | Connect to remote Chrome session           |
| `--default_timeout`    | Operation timeout (default: 60s)           |

---

## 🛠 Development

```bash
# Setup
bin/setup

# Run tests
rake spec

# Open interactive console
bin/console
```

---

## 📜 License

This project is licensed under the [MIT License](https://opensource.org/licenses/MIT).
