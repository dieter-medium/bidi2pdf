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
      port: 0,
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

  # rubocop:disable RSpec/BeforeAfterAll
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
  end

  after(:all) do
    @container&.stop if @container&.running?
    @container&.remove
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
end
