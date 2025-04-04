# frozen_string_literal: true

require "spec_helper"
require "pdf-reader"
require "testcontainers"

RSpec.describe Bidi2pdf::Launcher do
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
  let(:tmp_dir) { File.expand_path("../tmp", __dir__) }

  def host = @container.host

  def port = @container.mapped_port(80)

  before(:all) do
    Bidi2pdf.configure do |config|
      config.logger.level = Logger::INFO

      Chromedriver::Binary.configure do |c|
        c.logger.level = Logger::INFO
      end
    end

    root = File.expand_path("../fixtures", __dir__)

    nginx_conf = File.expand_path("../../docker/nginx/default.conf", __dir__)
    htpasswd = File.expand_path("../../docker/nginx/htpasswd", __dir__)
    html_dir = File.expand_path("../fixtures", __dir__)

    @container = Testcontainers::DockerContainer.new(
      "nginx:1.27-bookworm",
      exposed_ports: [80],
      filesystem_binds: {
        nginx_conf.to_s => "/etc/nginx/conf.d/default.conf",
        htpasswd.to_s => "/etc/nginx/conf.d/.htpasswd",
        html_dir.to_s => "/var/www/html"
      }
    )

    @container.start

    Timeout.timeout(15) do
      loop do
        response = nil
        if @container.running? && @container.mapped_port(80) != 0
          response = Net::HTTP.get_response(URI("http://#{host}:#{port}/sample.html"))
        end
        break if response&.code&.to_i == 200

        sleep 0.5
      rescue StandardError
        puts "Waiting for container to start"
      end
    end

    @golden_sample_text = nil
    @golden_sample_pages = nil

    golden_sample = File.join(root, "sample.pdf")

    PDF::Reader.open(golden_sample) do |reader|
      @golden_sample_text = reader.pages.map(&:text)
      @golden_sample_pages = reader.page_count
    end

    # in order to speed things up, we start chromedriver here, once, for all the tests
    @chromedriver_manager = Bidi2pdf::ChromedriverManager.new(port: 0, headless: true)
    @chromedriver_manager.start
  end

  after(:all) do
    @container&.stop if @container&.running?
    @container&.remove
    @chromedriver_manager&.stop
  end
  # rubocop:enable RSpec/BeforeAfterAll

  after do
    launcher&.stop
  end

  context "with basic auth" do
    let(:url) { "http://#{host}:#{port}/basic/sample.html" }
    let(:auth) { { username: "admin", password: "secret" } }

    include_examples "a PDF downloader"
  end

  context "with api key" do
    let(:url) { "http://#{host}:#{port}/header/sample.html" }
    let(:headers) { { "x-api-key" => "secret" } }

    include_examples "a PDF downloader"
  end

  context "with api cookie" do
    let(:url) { "http://#{host}:#{port}/cookie/sample.html" }
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

    let(:url) { "http://#{host}:#{port}/sample-without-page-settings.html" }
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
      failure_output = File.join(tmp_dir, "pdf-files", "test-failure-#{Time.now.to_i}.pdf")
      FileUtils.mkdir_p(File.dirname(failure_output))
      File.binwrite(failure_output, pdf_data)
      puts "Test failed! PDF saved to: #{failure_output}"
      raise e
    end
  end
end
