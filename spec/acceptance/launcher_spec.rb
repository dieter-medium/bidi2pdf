# frozen_string_literal: true

require "spec_helper"
require "pdf-reader"

RSpec.describe "PDF Generation", :nginx do
  subject(:launcher) do
    Bidi2pdf::Launcher.new(
      url: url,
      inputfile: nil,
      output: output,
      cookies: cookies,
      headers: headers,
      auth: auth,
      remote_browser_url: @chromedriver_manager.session_url,
      headless: true,
      wait_window_loaded: true,
      wait_network_idle: true,
      print_options: print_options,
      network_log_format: :pdf
    )
  end

  # Default values
  let(:url) { nginx_url "/sample.html" }
  let(:output) { nil }
  let(:headers) { nil }
  let(:auth) { nil }
  let(:cookies) { nil }
  let(:print_options) { {} }

  before(:all) do
    Bidi2pdf.configure do |config|
      config.logger.level = Logger::INFO
      config.network_events_logger.level = Logger::INFO

      Chromedriver::Binary.configure { |c| c.logger.level = Logger::INFO }
    end

    tmp_dir = random_tmp_dir("chromedriver")
    FileUtils.mkdir_p(tmp_dir)

    Chromedriver::Binary.configure do |config|
      @old_install_dir = config.install_dir
      config.install_dir = tmp_dir
    end

    @golden_sample_text = nil
    @golden_sample_pages = nil
    @golden_sample_image = fixture_file("img.jpg")

    golden_sample = fixture_file("sample.pdf")

    PDF::Reader.open(golden_sample) do |reader|
      @golden_sample_text = reader.pages.map(&:text)
      @golden_sample_pages = reader.page_count
    end

    @chromedriver_manager = Bidi2pdf::ChromedriverManager.new(port: 0, headless: true)
    @chromedriver_manager.start
  end

  after(:all) do
    @chromedriver_manager&.stop

    Bidi2pdf.configure do |config|
      config.network_events_logger.level = Logger::FATAL
    end

    Chromedriver::Binary.configure do |config|
      current_dir = config.install_dir
      FileUtils.rm_rf(current_dir)
      config.install_dir = @old_install_dir
    end
  end

  after do
    launcher&.stop
  end

  describe "As a user with basic authentication credentials" do
    let(:url) { nginx_url "/basic/sample.html" }
    let(:auth) { { username: "admin", password: "secret" } }

    it_behaves_like "a PDF downloader"
  end

  describe "As a user with an API key" do
    let(:url) { nginx_url "/header/sample.html" }
    let(:headers) { { "x-api-key" => "secret" } }

    it_behaves_like "a PDF downloader"
  end

  describe "As a user with an authentication cookie" do
    let(:url) { nginx_url "/cookie/sample.html" }
    let(:cookies) { { "auth" => "secret" } }

    it_behaves_like "a PDF downloader"
  end

  describe "As a user who needs custom PDF formatting" do
    let(:url) { nginx_url "/sample-without-page-settings.html" }
    let(:print_options) do
      {
        background: true,
        orientation: "landscape",
        margin: { top: 0.5, bottom: 0.75, left: 0.5, right: 0.5 },
        page: { width: 21.0, height: 29.7 },
        pageRanges: ["1-2"],
        scale: 0.9,
        shrinkToFit: true
      }
    end

    it "I can generate a PDF with limited page range" do
      pdf_data = Base64.decode64(launcher.launch)

      with_pdf_debug(pdf_data) do
        io = StringIO.new(pdf_data)

        PDF::Reader.open(io) do |reader|
          expect(reader.page_count).to eq(2)
        end
      end
    end

    it "I can generate a PDF in landscape orientation" do
      pdf_data = Base64.decode64(launcher.launch)

      with_pdf_debug(pdf_data) do
        io = StringIO.new(pdf_data)

        PDF::Reader.open(io) do |reader|
          page = reader.pages.first
          expect(page.attributes[:MediaBox][2]).to be > page.attributes[:MediaBox][3]
        end
      end
    end

    it "I can see the expected content in my generated PDF" do
      pdf_data = Base64.decode64(launcher.launch)

      with_pdf_debug(pdf_data) do
        io = StringIO.new(pdf_data)

        PDF::Reader.open(io) do |reader|
          text = reader.pages.map(&:text).join
          expect(text).to include("PDF Rendering Sample")
        end
      end
    end
  end

  describe "As a user with a local html file" do
    subject(:launcher) do
      Bidi2pdf::Launcher.new(
        url: nil,
        inputfile: fixture_file("sample.html"),
        output: output,
        cookies: cookies,
        headers: headers,
        auth: auth,
        remote_browser_url: @chromedriver_manager.session_url,
        headless: true,
        wait_window_loaded: false, # the assets have relative paths and are not loaded, so we can't wait for the event
        wait_network_idle: true,
        print_options: print_options
      )
    end

    it "I can generate a PDF file" do
      pdf_data = Base64.decode64(launcher.launch)

      with_pdf_debug(pdf_data) do
        io = StringIO.new(pdf_data)

        PDF::Reader.open(io) do |reader|
          text = reader.pages.map(&:text).join
          expect(text).to include("PDF Rendering Sample")
        end
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
