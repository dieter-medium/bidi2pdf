[![Build Status](https://github.com/dieter-medium/bidi2pdf/actions/workflows/ruby.yml/badge.svg)](https://github.com/dieter-medium/bidi2pdf/blob/main/.github/workflows/ruby.yml)
[![Maintainability](https://api.codeclimate.com/v1/badges/6425d9893aa3a9ca243e/maintainability)](https://codeclimate.com/github/dieter-medium/bidi2pdf/maintainability)
[![Gem Version](https://badge.fury.io/rb/bidi2pdf.svg)](https://badge.fury.io/rb/bidi2pdf)
[![Test Coverage](https://api.codeclimate.com/v1/badges/6425d9893aa3a9ca243e/test_coverage)](https://codeclimate.com/github/dieter-medium/bidi2pdf/test_coverage)

# Bidi2pdf

Bidi2pdf is a Ruby gem that generates high-quality PDFs from web pages using Chrome's BiDi (BiDirectional) protocol. It
offers precise control over PDF generation with support for modern web technologies.

## Features

- **Simple CLI** - Generate PDFs with a single command
- **Rich Configuration** - Customize with cookies, headers, and authentication
- **Waiting Conditions** - Wait for window loaded or network idle
- **Headless Support** - Run without a visible browser
- **Docker Ready** - Easy containerization
- **Modern Architecture** - Uses Chrome's BiDi protocol for better control

## Installation

Add to your application's Gemfile:

```ruby
gem 'bidi2pdf'
```

Or install manually:

```bash
$ gem install bidi2pdf
```

### Dependencies

- **Ruby**: 3.3 or higher
- **Bidi2pdf** automatically manages ChromeDriver binaries through
  the [chromedriver-binary](https://github.com/dieter-medium/chromedriver-binary) gem, which:
  Downloads and installs the ChromeDriver version matching your installed Chrome/Chromium browser
  Eliminates the need to manually install or update ChromeDriver
  Ensures compatibility between Chrome and ChromeDriver versions

## Usage

### Basic Command Line Usage

```bash
bidi2pdf render --url https://example.com --output example.pdf
```

### Advanced Options

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

### Ruby API

```ruby
require 'bidi2pdf'

launcher = Bidi2pdf::Launcher.new(
  url: 'https://example.com',
  output: 'example.pdf', # nil for base64 encoded string as result of launcher.launch
  cookies: { 'session' => 'abc123' },
  headers: { 'X-API-KEY' => 'token' },
  auth: { username: 'admin', password: 'password' },
  wait_window_loaded: true,
  wait_network_idle: true
)

launcher.launch

# see Bidi2pdf::SessionRunner for more options
```

#### Step by step

```ruby 
require "bidi2pdf"

# 1. Setup session: Local or Remote?
# ----------------------------------

# Option A: Remote browser (headless by default)
# First ensure remote service is running e.g., `docker compose -f docker/docker-compose.yml up -d`
session = Bidi2pdf::Bidi::Session.new(
  session_url: "http://localhost:9092/session",
  headless: true, # usually mandatory for remote sessions
)

# Option B: Local browser (you control the session lifecycle)
manager = Bidi2pdf::ChromedriverManager.new(headless: false)
manager.start
session = manager.session

session.start
session.client.on_close { Bidi2pdf.logger.info "WebSocket session closed" }

# 2. Create browser context, window, and tab
# ------------------------------------------
browser = session.browser
user_context = browser.create_user_context
window = user_context.create_browser_window
tab = window.create_browser_tab

# 3. Configure session (Optional)
# -------------------------------

# Set session cookies (if needed)
tab.set_cookie(
  name: "auth",
  value: "secret",
  domain: "www.example.com",
  secure: true
)

# Inject custom API headers (if needed)
tab.add_headers(
  url_patterns: [
    {
      type: "pattern",
      protocol: "https",
      hostname: "www.example.com",
      port: "443"
    }
  ],
  headers: [
    { name: "X-API-KEY", value: "12345678" }
  ]
)

# Enable basic auth (if needed)
tab.basic_auth(
  url_patterns: [
    {
      type: "pattern",
      protocol: "https",
      hostname: "www.example.com",
      port: "443"
    }
  ],
  username: "username",
  password: "secret"
)

# 4. Open page and wait for loading completion
# --------------------------------------------
tab.open_page "https://www.example.com"

# Wait until all network activity completes.
# CAUTION: be careful with endpoints that constantly poll or stream data
tab.wait_until_all_finished

# Alternatively, explicitly wait using JavaScript polling (uncomment and customize if needed)
# tab.execute_script <<-JS
#   new Promise(resolve => {
#     const check = () => window.loaded ? resolve('done') : setTimeout(check, 100);
#     check();
#   });
# JS

# 5. Generate PDF from page
# -------------------------
# Save PDF directly to file
tab.print("my.pdf")

# Or handle PDF data in memory
# tab.print do |base64_encoded_pdf|
#   pdf_data = Base64.decode64(base64_encoded_pdf)
#   # ... custom actions (e.g., store in database, send via email)
# end

# 6. Cleanup resources
# --------------------
tab.close
window.close

session.close if session
manager&.stop

```

## Docker Support

Build and run with Docker:

```bash
# Build gem and Docker image
rake build
docker build -t bidi2pdf -f docker/Dockerfile .

# Generate PDF using Docker
docker run -it --rm -v ./output:/reports bidi2pdf \
  bidi2pdf render --url=https://example.com --output /reports/example.pdf
```

### Test it with docker compose

```bash
rake build
docker compose -f docker/docker-compose.yml up -d

# simple example
docker compose -f docker/docker-compose.yml exec app bidi2pdf render --url=http://nginx/sample.html --wait_window_loaded --wait_network_idle --output /reports/simple.pdf

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

## Configuration Options

| Option                 | Description                                                                                                         |
|------------------------|---------------------------------------------------------------------------------------------------------------------|
| `--url`                | The URL to render (required)                                                                                        |
| `--output`             | Output PDF filename (default: output.pdf)                                                                           |
| `--cookie`             | Cookies in name=value format                                                                                        |
| `--header`             | HTTP headers in name=value format                                                                                   |
| `--auth`               | Basic auth credentials (user:pass)                                                                                  |
| `--headless`           | Run Chrome in headless mode (default: true)                                                                         |
| `--port`               | Port for ChromeDriver (0 = auto)                                                                                    |
| `--wait_window_loaded` | Wait for the window to be fully loaded. You need to set a variable `window.loaded`. See ./spec/fixtures/sample.html |
| `--wait_network_idle`  | Wait for network to be idle                                                                                         |
| `--log_level`          | Log level (debug, info, warn, error, fatal)                                                                         |
| `--remote_browser_url` | URL of the remote Chrome instance (default: nil)                                                                    |
| `--default_timeout`    | Default timeout for operations (default: 60 seconds)                                                                |

## Development

After checking out the repo:

1. Run `bin/setup` to install dependencies
2. Run `rake spec` to run the tests
3. Run `bin/console` for an interactive prompt

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).