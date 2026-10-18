---
name: pdf-specs
description: This skill should be used when writing or fixing RSpec specs that render PDFs or drive pages with bidi2pdf - asserting text, page count or images in a generated PDF, starting a Chrome container for the suite, or a browser spec that is flaky, times out or sees an empty page.
---

# RSpec specs with bidi2pdf's test helpers

bidi2pdf ships RSpec matchers for PDFs and helpers that start a chromedriver container for the
suite. This skill is how to use them, and the mistakes that made such specs flaky before.

**Does not:** replace a project's own spec conventions - follow those for naming and layout. And it
does not cover bidi2pdf-rails' own test helpers (see that gem).

## 1. Set up

```ruby
# spec/spec_helper.rb
require "bidi2pdf/test_helpers"             # matchers and file helpers; needs pdf-reader, diff-lcs, unicode_utils
require "bidi2pdf/test_helpers/images"      # only for contains_pdf_image (ruby-vips, dhash-vips)
require "bidi2pdf/test_helpers/testcontainers" # only to start Chrome in Docker for the suite
```

Add the gems the comments name to the test group of the Gemfile; each helper warns when one is
missing instead of failing the suite.

## 2. Assert on the PDF

```ruby
pdf = tab.print                                   # base64; a path or raw bytes work too
expect(pdf).to have_pdf_page_count(2)
expect(pdf).to contains_pdf_text("Invoice #123")
expect(pdf).to contains_pdf_text(/Total: \d+/).at_page(2)
expect(pdf).to match_pdf_text(expected_pdf)       # the whole text equal, after cleaning both texts
expect(pdf).to contains_pdf_image("spec/fixtures/logo.png").at_page(1) # perceptually similar, tolerance: 10
```

- PDF text extraction lays words out by position: a sidebar and a main column can interleave on
  one line. Assert on words that occur once, not on whole lines.
- One render, several fields of it, is one example; do not render the same PDF again per field.

## 3. A Chrome for the suite

Tag examples `:chromedriver`: the helper starts the chromedriver container once for the suite
(Docker required) and gives the example `session_url`, `create_session(session_url)` and
`with_tab(session_url) { |tab| ... }`, which opens and always closes the session. Without Docker,
point the specs at an existing chromedriver instead (a `remote-chrome` service, see that skill) and
skip the tag.

## 4. Browser specs that stay green

- **Wait on the outcome, not on the network.** `wait_until_network_idle` only sees requests that
  have started; a debounced search or a deferred fetch starts later, and the assertion runs too
  early. Poll for the DOM state you expect (a selector that appears, a text that changes), with a
  deadline that raises.
- **A script that throws returns no value.** `execute_script` returns the BiDi result: check
  `result["type"]` - an `"exception"` there, not a `nil` value, means your selector or script
  failed.
- **Visible is not the same as present.** A scripted `.click()` works on hidden elements; a real
  user cannot click them. Navigate to the state where the element is visible before asserting on
  it.
- **Close cleanly.** Close tab, window and session in an `ensure`; let in-flight requests finish
  before the test server tears down its database connection, or a request still rendering fails
  outside any example.
- **Ports.** A test server on a fixed port collides with a running development server: pick a free
  one, and let the browser reach it by a name it resolves.
- **Locale-dependent output.** Date fields render in the browser's locale; pin `LANG` on the browser
  container and set dates as ISO strings.
