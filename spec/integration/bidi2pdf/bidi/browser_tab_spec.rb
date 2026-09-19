# frozen_string_literal: true

require "spec_helper"
require "socket"

RSpec.describe Bidi2pdf::Bidi::BrowserTab, :chromedriver, :nginx, :session do
  def reporter
    RSpec.configuration.reporter
  end

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

        reporter.message("Generated file: #{file_name} (#{file_size} bytes, type: #{file_type})")
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
      end.to perform_under(1000).ms.warmup(1).times.sample(10).times
    end

    context "when using multiple browser tabs" do
      it "can generate multiple PDF files in parallel" do
        url = nginx_url "simple_with_pagedjs.html", use_alias: true

        # warmup
        create_pdf_thread(url, session).value

        threads = 10.times.map { create_pdf_thread url, session }

        pdfs = threads.map(&:value)

        expect(pdfs).to all(have_pdf_page_count(1))
      end
    end
  end

  describe "#screenshot" do
    let(:tmp_path) { random_tmp_dir }
    let(:png_path) { File.join(tmp_path, "test.png") }

    before do
      FileUtils.mkdir_p(tmp_path)
      browser_tab.navigate_to "file:///var/www/html/simple.html"
    end

    after do
      FileUtils.rm_f(tmp_path)
    end

    it "saves a real screenshot to the given filename" do
      browser_tab.screenshot(png_path)

      expect(File.size(png_path)).to be > 0
    end

    it "returns the image data, when no filename is given" do
      png_base64 = browser_tab.screenshot

      expect(Base64.decode64(png_base64)).not_to be_empty
    end
  end

  describe "#set_viewport" do
    before do
      # bidi2pdf/test_helpers/images is this gem's one sanctioned opt-in gateway to ruby-vips (a
      # dev-only dependency - see bidi2pdf.gemspec) - it already rescues a missing vips/dhash-vips
      # with a warn (not a raise), and now also calls Vips.block_untrusted(true) once for every
      # consumer of it (CVE-2026-66066 hardening). Routed through it here, rather than a bare
      # `require "vips"`, so this test never has its own second, out-of-band way to load/harden
      # vips - every other describe block in this file stays independent of libvips either way.
      require "bidi2pdf/test_helpers/images"

      # images.rb's own require swallows LoadError (warns instead of raising), so check the
      # constant rather than rescue - skips with a message instead of failing when vips isn't
      # installed, keeping the suite green for anyone who doesn't want this dependency.
      unless defined?(Vips::Image)
        skip "ruby-vips/libvips not installed - install libvips to run this example " \
               "(it's a dev-only, opt-in dependency; see bidi2pdf.gemspec)"
      end

      browser_tab.navigate_to "file:///var/www/html/simple.html"
    end

    it "changes the dimensions of a subsequent viewport screenshot" do
      browser_tab.set_viewport(width: 800, height: 600)

      # origin: "viewport" (not #screenshot's own "document" default) captures exactly the set
      # viewport, regardless of the fixture page's own content size - the direct effect of
      # #set_viewport, not incidentally the same size because the page happens to be small.
      image = Vips::Image.new_from_buffer(Base64.decode64(browser_tab.screenshot(origin: "viewport")), "")

      expect([image.width, image.height]).to eq([800, 600])
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

  def create_pdf_thread(url, session)
    Thread.new do
      browser = session.browser
      context = browser.create_user_context
      window = context.create_browser_window
      tab = window.create_browser_tab

      begin
        tab.navigate_to url
        tab.wait_until_network_idle
        tab.wait_until_page_loaded

        tab.print
      ensure
        tab&.close
        window&.close
        context&.close
      end
    end
  end
end
