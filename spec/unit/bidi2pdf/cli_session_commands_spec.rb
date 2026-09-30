# frozen_string_literal: true

require "spec_helper"
require "bidi2pdf/cli"

RSpec.describe Bidi2pdf::CLI do
  let(:session_url) { "http://remote-chrome:3000/session" }
  let(:chromedriver) { FakeChromedriver.new(%w[old young]) }
  let(:dir) { Dir.mktmpdir }

  # Only the network boundary is replaced: chromedriver's HTTP API and attaching to each session.
  before do
    api = chromedriver.api(session_url)
    allow(Bidi2pdf::ChromedriverApi).to receive(:new).and_return(api)
    allow(Bidi2pdf::ChromeSweeper::Inspector).to receive(:new).and_return(FakeSessionInspector.build({ "old" => 900.4, "young" => 10 }))
    allow(Dir).to receive(:tmpdir).and_return(dir)
  end

  after { FileUtils.rm_rf(dir) }

  # Runs the CLI; returns [exit status (nil when it did not exit), stdout].
  def run_cli(*args)
    original = $stdout
    $stdout = StringIO.new
    status = nil
    begin
      described_class.start(args)
    rescue SystemExit => e
      status = e.status
    end
    [status, $stdout.string]
  ensure
    $stdout = original
  end

  describe "sessions" do
    it "lists every session as JSON, without any page content" do
      _, out = run_cli("sessions", "--remote-browser-url", session_url, "--json")

      expect(JSON.parse(out)).to eq([
                                      { "id" => "old", "age" => 900, "source" => "tab", "tabs" => 1, "responsive" => true },
                                      { "id" => "young", "age" => 10, "source" => "tab", "tabs" => 1, "responsive" => true }
                                    ])
    end

    it "prints one line per session" do
      _, out = run_cli("sessions", "--remote-browser-url", session_url)

      expect(out.lines.size).to eq(2)
    end
  end

  describe "sweep" do
    it "closes sessions older than --older-than" do
      run_cli("sweep", "--remote-browser-url", session_url, "--scope", "all", "--older-than", "600")

      expect(chromedriver.sessions).to eq(["young"])
    end

    it "closes nothing in a dry run" do
      run_cli("sweep", "--remote-browser-url", session_url, "--scope", "all", "--older-than", "600", "--dry-run")

      expect(chromedriver.sessions).to eq(%w[old young])
    end

    it "reports what it closed as JSON" do
      _, out = run_cli("sweep", "--remote-browser-url", session_url, "--scope", "all", "--older-than", "600", "--json")

      expect(JSON.parse(out)["closed"]).to eq([{ "id" => "old", "age" => 900, "why" => "orphan" }])
    end

    it "exits 1 when the session limit is still exceeded" do
      status, = run_cli("sweep", "--remote-browser-url", session_url, "--scope", "all", "--max-sessions", "1", "--min-age", "3600")

      expect(status).to eq(1)
    end

    it "reports an invalid setting as a CLI error" do
      status, = run_cli("sweep", "--remote-browser-url", session_url, "--max-sessions", "0")

      expect(status).to eq(1)
    end
  end
end
