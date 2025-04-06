# frozen_string_literal: true

require "spec_helper"
require "pdf-reader"

RSpec.describe Bidi2pdf::Launcher, :nginx do
  subject(:launcher) do
    described_class.new(
      url: url,
      output: output, # nil return the base64 string
      cookies: cookies,
      headers: headers,
      auth: auth,
      remote_browser_url: @chromedriver_manager.session_url, # speed things up
      headless: true,
      wait_window_loaded: true,
      wait_network_idle: true
    )
  end

  let(:output) { nil }
  let(:headers) { nil }
  let(:auth) { nil }
  let(:cookies) { nil }

  before(:all) do
    Bidi2pdf.configure do |config|
      config.logger.level = Logger::INFO

      Chromedriver::Binary.configure do |c|
        c.logger.level = Logger::INFO
      end
    end

    tmp_dir = random_tmp_dir("chromedriver")
    FileUtils.mkdir_p(tmp_dir)

    Chromedriver::Binary.configure do |config|
      @old_install_dir = config.install_dir

      config.install_dir = tmp_dir
    end

    @golden_sample_text = nil
    @golden_sample_pages = nil

    golden_sample = fixture_file("sample.pdf")

    PDF::Reader.open(golden_sample) do |reader|
      @golden_sample_text = reader.pages.map(&:text)
      @golden_sample_pages = reader.page_count
    end

    # in order to speed things up, we start chromedriver here, once, for all the tests
    @chromedriver_manager = Bidi2pdf::ChromedriverManager.new(port: 0, headless: true)
    @chromedriver_manager.start
  end

  after(:all) do
    @chromedriver_manager&.stop

    Chromedriver::Binary.configure do |config|
      current_dir = config.install_dir

      FileUtils.rm_rf(current_dir)

      config.install_dir = @old_install_dir
    end
  end
  # rubocop:enable RSpec/BeforeAfterAll

  after do
    launcher&.stop
  end

  context "with basic auth" do
    let(:url) { nginx_url "/basic/sample.html" }
    let(:auth) { { username: "admin", password: "secret" } }

    include_examples "a PDF downloader"
  end

  context "with api key" do
    let(:url) { nginx_url "/header/sample.html" }
    let(:headers) { { "x-api-key" => "secret" } }

    include_examples "a PDF downloader"
  end

  context "with api cookie" do
    let(:url) { nginx_url "/cookie/sample.html" }
    let(:cookies) { { "auth" => "secret" } }

    include_examples "a PDF downloader"
  end

  context "with all print parameters" do
    # css settings ovveride the print settings, so we need a "clean" page
    subject(:launcher) do
      described_class.new(
        url: url,
        output: nil,
        cookies: cookies,
        headers: headers,
        auth: auth,
        remote_browser_url: @chromedriver_manager.session_url,
        headless: true,
        wait_window_loaded: true,
        wait_network_idle: true,
        print_options: print_options
      )
    end

    let(:url) { nginx_url "/sample-without-page-settings.html" }
    let(:print_options) do
      {
        background: true,
        orientation: "landscape",
        margin: {
          top: 0.5,
          bottom: 0.75,
          left: 0.5,
          right: 0.5
        },
        page: {
          width: 21.0,
          height: 29.7
        },
        pageRanges: ["1-2"],
        scale: 0.9,
        shrinkToFit: true
      }
    end

    it "prints only the expected pages" do
      pdf_data = Base64.decode64(launcher.launch)

      with_pdf_debug(pdf_data) do
        io = StringIO.new(pdf_data)

        PDF::Reader.open(io) do |reader|
          # Check page count (should be 2 due to pageRanges: ["1-2"])
          expect(reader.page_count).to eq(2)
        end
      end
    end

    it "prints landscape mode" do
      pdf_data = Base64.decode64(launcher.launch)

      with_pdf_debug(pdf_data) do
        io = StringIO.new(pdf_data)

        PDF::Reader.open(io) do |reader|
          # Verify landscape orientation by checking dimensions
          # In landscape mode, width > height
          page = reader.pages.first
          expect(page.attributes[:MediaBox][2]).to be > page.attributes[:MediaBox][3]
        end
      end
    end

    it "prints text" do
      pdf_data = Base64.decode64(launcher.launch)

      with_pdf_debug(pdf_data) do
        io = StringIO.new(pdf_data)

        PDF::Reader.open(io) do |reader|
          # Check content - the file should still contain expected text
          text = reader.pages.map(&:text).join
          expect(text).to include("PDF Rendering Sample")
        end
      end
    end

    def with_pdf_debug(pdf_data)
      yield
    rescue RSpec::Expectations::ExpectationNotMetError => e
      failure_output = tmp_file("pdf-files", "test-failure-#{Time.now.to_i}.pdf")
      FileUtils.mkdir_p(File.dirname(failure_output))
      File.binwrite(failure_output, pdf_data)
      puts "Test failed! PDF saved to: #{failure_output}"
      raise e
    end
  end
end
