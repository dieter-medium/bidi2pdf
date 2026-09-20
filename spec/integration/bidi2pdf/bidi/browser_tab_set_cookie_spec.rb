# frozen_string_literal: true

require "spec_helper"

# Does a cookie set through #set_cookie actually reach the server? The unit spec only checks the
# command's shape; storage.setCookie can succeed and the cookie still never be attached. Everything
# here is observed client-side (the request Chrome really sent, and document.cookie), so no
# cookie-checking server is needed.
RSpec.describe Bidi2pdf::Bidi::BrowserTab, "#set_cookie", :chromedriver, :nginx, :session do
  subject(:browser_tab) { browser_window.create_browser_tab }

  let(:browser_window) { user_context.create_browser_window }
  let(:user_context) { browser.create_user_context }
  let(:browser) { session.browser }
  let(:session) { create_session session_url }

  let(:nginx_cookie_url) { nginx_url("/cookie/sample.html", use_alias: true) }

  # Chrome runs inside the chromedriver container, so its "localhost" is that container - and the
  # one thing listening there is chromedriver itself. GET /status is a plain 200, on a non-default
  # port: the same shape as an app served at http://localhost:<port>.
  let(:localhost_url) { "http://localhost:#{chromedriver_container.port}/status" }

  after do
    report_browser_version
    session.close
  end

  def reporter
    RSpec.configuration.reporter
  end

  # A result here only means something for the Chrome that produced it.
  def report_browser_version
    user_agent = browser_tab.execute_script("navigator.userAgent").dig("result", "value")
    reporter.message("set_cookie spec ran against: #{user_agent}")
  rescue StandardError => e
    reporter.message("set_cookie spec: browser version unavailable (#{e.class})")
  end

  # The cookies Chrome attached to the main-document request of this navigation, as name => value.
  # Matched by "navigation" (only the document request has one), not by URL - Chrome normalizes it.
  def cookies_sent_to(url)
    captured = Thread::Queue.new

    browser_tab.client.on_event("network.beforeRequestSent") do |data|
      captured << data.dig("params", "request", "cookies") if document_request?(data["params"])
    end

    navigate_ignoring_http_status(url)

    cookies_by_name(captured.pop(timeout: 5) || [])
  end

  def document_request?(params)
    params["context"] == browser_tab.browsing_context_id && !params["navigation"].nil?
  end

  def cookies_by_name(cookies)
    cookies.to_h { |cookie| [cookie["name"], cookie.dig("value", "value")] }
  end

  # beforeRequestSent fires before any response, so an error status must not hide what was sent.
  def navigate_ignoring_http_status(url)
    browser_tab.navigate_to(url)
  rescue Bidi2pdf::NavigationError
    nil
  end

  def document_cookie
    browser_tab.execute_script("document.cookie").dig("result", "value")
  end

  context "with the cookie domain of a container alias (control - launcher_spec relies on it)" do
    it "attaches the cookie to the request" do
      browser_tab.set_cookie(name: "auth", value: "secret", domain: "nginx", secure: false)

      expect(cookies_sent_to(nginx_cookie_url)).to include("auth" => "secret")
    end

    # A MessageVerifier-signed value is base64--hexdigest: "+", "/", "=" and "--" all occur.
    it "transmits a value with base64 and separator characters byte-identical" do
      browser_tab.set_cookie(name: "auth", value: "a+b/c==--d", domain: "nginx", secure: false)

      expect(cookies_sent_to(nginx_cookie_url)).to include("auth" => "a+b/c==--d")
    end
  end

  context "with the cookie domain localhost" do
    before { browser_tab.set_cookie(name: "auth_token", value: "secret", domain: "localhost", secure: false) }

    it "attaches the cookie to the request" do
      expect(cookies_sent_to(localhost_url)).to include("auth_token" => "secret")
    end

    it "exposes the cookie to the document" do
      navigate_ignoring_http_status(localhost_url)

      expect(document_cookie).to include("auth_token=secret")
    end
  end
end
