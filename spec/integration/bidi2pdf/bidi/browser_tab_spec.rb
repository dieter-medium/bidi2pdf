# frozen_string_literal: true

require "spec_helper"
require "socket"

RSpec.describe Bidi2pdf::Bidi::BrowserTab, :chromedriver, :nginx, :session do
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

  describe "#print" do
    let(:tmp_path) { random_tmp_dir }

    before do
      FileUtils.mkdir_p(tmp_path)
    end

    after do
      Dir.glob("#{tmp_path}/*").each do |file|
        next if File.directory?(file)

        file_size = File.size(file)
        file_name = File.basename(file)
        file_type = File.extname(file)

        puts "Generated file: #{file_name} (#{file_size} bytes, type: #{file_type})"
      end

      FileUtils.rm_f(tmp_path)
    end

    it "I can generate a PDF file in less than 5 seconds", :benchmark do
      id = 0
      expect do
        pdf_path = File.join(tmp_path, "#{id += 1}-test.pdf")
        new_user_context = browser.create_user_context
        new_browser_window = new_user_context.create_browser_window
        new_browser_tab = new_browser_window.create_browser_tab

        new_browser_tab.navigate_to "file:///var/www/html/simple.html"

        new_browser_tab.print(pdf_path)

        nil
      ensure
        new_browser_tab&.close
        new_browser_window&.close
        new_user_context&.close
      end.to perform_under(600).ms.warmup(1).times.sample(10).times
    end
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

  describe "#inject_style" do
    before do
      browser_tab.navigate_to "file:///var/www/html/simple.html"
    end

    context "when a style is injected" do
      it "injects the given style" do
        browser_tab.inject_style content: <<~CSS, id: 1
          body {
            background-color: red;
          }
        CSS

        response = browser_tab.execute_script("result = window.getComputedStyle(document.body).backgroundColor;", wrap_in_promise: true)

        expect(response.dig("result", "value")).to eq("rgb(255, 0, 0)")
      end
    end

    context "when a style file is loaded from an url" do
      it "loads a remote style" do
        browser_tab.inject_style url: "file:///var/www/html/simple.css", id: 1

        response = browser_tab.execute_script("result = window.getComputedStyle(document.body).backgroundColor;", wrap_in_promise: true)

        expect(response.dig("result", "value")).to eq("rgb(0, 0, 255)")
      end

      it "raises an error when the style file is not found" do
        expect { browser_tab.inject_style url: "file:///var/www/html/does-not-exists.css", id: 1 }.to raise_error(Bidi2pdf::StyleInjectionError)
      end
    end
  end

  describe "#navigate_to" do
    context "when the http status code is error" do
      it "raises an error" do
        expect { browser_tab.navigate_to(nginx_url("does-not-exists")) }.to raise_error(Bidi2pdf::NavigationError)
      end
    end
  end
end
