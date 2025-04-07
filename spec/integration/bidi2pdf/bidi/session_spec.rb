# frozen_string_literal: true

require "spec_helper"
require "socket"

RSpec.describe Bidi2pdf::Bidi::Session, :chromedriver do
  subject(:session) { described_class.new(session_url: current_session_url, headless: headless) }

  let(:current_session_url) { session_url }
  let(:headless) { true }

  before(:all) do
    Bidi2pdf.configure do |config|
      config.logger.level = Logger::DEBUG
      Chromedriver::Binary.configure { |c| c.logger.level = Logger::DEBUG }
    end
  end

  after do
    session.close
  end

  describe "#start" do
    it "starts the session" do
      session.start
      expect(session).to be_started
    end

    context "when headless is disabled within a container" do
      let(:headless) { false }

      it "raises an error" do
        expect { session.start }.to raise_error(Bidi2pdf::SessionNotStartedError)
      end
    end

    context "when host is invalid in session URL" do
      let(:current_session_url) do
        server = TCPServer.new("127.0.0.1", 0)
        port = server.addr[1]
        server.close

        "http://localhost:#{port}/session"
      end

      it "raises an error" do
        expect { session.start }.to raise_error(Bidi2pdf::SessionNotStartedError)
      end
    end

    context "when endpoint is invalid in session URL" do
      let(:current_session_url) { "#{session_url}/invalid" }

      it "raises an error" do
        expect { session.start }.to raise_error(Bidi2pdf::SessionNotStartedError)
      end
    end
  end

  describe "#client" do
    context "when session is started" do
      before { session.start }

      it "returns a client instance" do
        expect(session.client).to be_a(Bidi2pdf::Bidi::Client)
      end
    end

    context "when session is not started" do
      it "returns nil" do
        expect(session.client).to be_nil
      end
    end
  end

  describe "#browser" do
    before { session.start }

    it "returns a browser instance" do
      expect(session.browser).to be_a(Bidi2pdf::Bidi::Browser)
    end
  end

  describe "#websocket_url" do
    context "when session URI scheme is ws or wss" do
      let(:current_session_url) { "ws://localhost:4444" }

      it "returns the websocket URL" do
        expect(session.send(:websocket_url)).to eq(current_session_url)
      end
    end

    context "when session URI scheme is not ws or wss" do
      it "creates a new session and returns the websocket URL" do
        expect(session.send(:websocket_url)).to match(%r{^ws://})
      end
    end
  end
end
