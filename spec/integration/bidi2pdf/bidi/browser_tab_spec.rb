# frozen_string_literal: true

require "spec_helper"
require "socket"

RSpec.describe Bidi2pdf::Bidi::BrowserTab, :chromedriver, :session do
  subject(:browser_tab) { browser_window.create_browser_tab }

  let(:browser_window) { user_context.create_browser_window }
  let(:user_context) { browser.create_user_context }
  let(:browser) { session.browser }

  let(:session) { create_session session_url }

  let(:log_output) { StringIO.new }
  let(:browser_console_logger) { Logger.new(log_output) }

  before(:all) do
    Bidi2pdf.configure do |config|
      config.logger.level = Logger::DEBUG
    end
  end

  after(:all) do
    Bidi2pdf.configure do |config|
      config.logger.level = Logger::INFO
    end
  end

  before do
    Bidi2pdf.configure do |config|
      config.browser_console_logger = browser_console_logger
      config.browser_console_logger.level = Logger::DEBUG
    end
  end

  after do
    Bidi2pdf.configure do |config|
      config.browser_console_logger = Logger.new($stdout)
      config.browser_console_logger.level = Logger::INFO
    end

    session.close
  end

  describe "#inject_script" do
    before do
      # a website is required to inject a script
      # browser_tab.render_html_content("<html><body>Hello, world!</body></html>")

      browser_tab.navigate_to "file:///var/www/html/simple.html"
    end

    context "when a script is injected" do
      it "executes the given script" do
        browser_tab.inject_script content: <<~JS, id: 1
          console.info({ a: 'Hello," world!' });
          console.warn('Hello, " world!');
        JS

        log_output.rewind
        logs = log_output.read

        expect(logs).to include(/WARN.*Hello, " world!/)
      end

      it "log only error messages when the inline script fails" do
        browser_tab.inject_script content: <<~JS, id: 1
          console.info({ a: 'Hello," world!' });
          throw new Error('This is a test error message');
        JS

        log_output.rewind
        logs = log_output.read

        expect(logs).to include(/ERROR.*Error: This is a test error message/)
      end
    end

    context "when a script file is loaded from an url" do
      it "loads a remote script" do
        browser_tab.inject_script url: "file:///var/www/html/simple.js", id: 1

        log_output.rewind
        logs = log_output.read

        expect(logs).to include(/ERROR.*Error: This is a test error message/)
      end

      it "raises an error when the script file is not found" do
        expect { browser_tab.inject_script url: "file:///var/www/html/does-not-exists.js", id: 1 }.to raise_error(Bidi2pdf::ScriptInjectionError)
      end
    end
  end
end
