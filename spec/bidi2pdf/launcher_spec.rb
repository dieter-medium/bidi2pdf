# frozen_string_literal: true

require "spec_helper"
require "webrick"
require "pdf-reader"

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

  def port = @server.config[:Port]

  # rubocop:disable RSpec/BeforeAfterAll
  before(:all) do
    Bidi2pdf.configure do |config|
      config.logger.level = Logger::INFO

      Chromedriver::Binary.configure do |c|
        c.logger.level = Logger::INFO
      end
    end

    root = File.expand_path("../fixtures", __dir__)

    user_db = WEBrick::HTTPAuth::Htpasswd.new("#{Dir.tmpdir}/webrick-htpasswd")
    user_db.set_passwd(nil, "admin", "secret")

    basic_auth = WEBrick::HTTPAuth::BasicAuth.new(
      Realm: "My Protected Server",
      UserDB: user_db,
      Logger: WEBrick::Log.new(File::NULL)
    )

    api_key = "secret"
    cookie_secret = "secret"

    @server = WEBrick::HTTPServer.new(
      Port: 0,
      DocumentRoot: root,
      AccessLog: [],
      Logger: WEBrick::Log.new(File::NULL)
    )

    # Middleware-like helper to serve files after checking something
    serve_if = lambda do |req, res, &condition|
      if condition.call(req)
        WEBrick::HTTPServlet::FileHandler.new(@server, root).service(req, res)
      else
        res.status = 403
        res.body = "Forbidden"
      end
    end

    @server.mount_proc("/basic") do |req, res|
      basic_auth.authenticate(req, res)
      WEBrick::HTTPServlet::FileHandler.new(@server, root).service(req, res)
    end

    @server.mount_proc("/api") do |req, res|
      serve_if.call(req, res) { req.header["x-api-key"]&.first == api_key }
    end

    @server.mount_proc("/cookie") do |req, res|
      serve_if.call(req, res) do
        cookie = req.cookies.find { |c| c.name == "auth" }
        cookie&.value == cookie_secret
      end
    end

    @server_thread = Thread.new { @server.start }

    @golden_sample_text = nil
    @golden_sample_pages = nil

    golden_sample = File.join(root, "sample.pdf")

    PDF::Reader.open(golden_sample) do |reader|
      @golden_sample_text = reader.pages.map(&:text)
      @golden_sample_pages = reader.page_count
    end

    # Wait for server to boot
    sleep 0.5
  end

  after(:all) do
    @server&.shutdown
    @server_thread.kill
  end
  # rubocop:enable RSpec/BeforeAfterAll

  after do
    launcher&.stop
  end

  context "with basic auth" do
    let(:url) { "http://localhost:#{port}/basic/sample.html" }
    let(:auth) { { username: "admin", password: "secret" } }

    include_examples "a PDF downloader"
  end

  context "with api key" do
    let(:url) { "http://localhost:#{port}/api/sample.html" }
    let(:headers) { { "x-api-key" => "secret" } }

    include_examples "a PDF downloader"
  end

  context "with api cookie" do
    let(:url) { "http://localhost:#{port}/cookie/sample.html" }
    let(:cookies) { { "auth" => "secret" } }

    include_examples "a PDF downloader"
  end
end
