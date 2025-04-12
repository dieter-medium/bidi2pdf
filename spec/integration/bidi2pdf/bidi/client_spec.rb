# frozen_string_literal: true

require "spec_helper"
require "socket"

RSpec.describe Bidi2pdf::Bidi::Client, :chromedriver, :session do
  subject(:client) { described_class.new(websocket_url) }

  let(:session) { create_session session_url }
  let(:websocket_url) { session.websocket_url }

  let(:cmd) do
    Class.new do
      include Bidi2pdf::Bidi::Commands::Base

      attr_accessor :cmd

      def method_name = cmd
    end.new
  end

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

  after do
    client.close
    session.close
  end

  describe "#start" do
    it "starts the client" do
      client.start
      expect(client).to be_started
    end
  end

  describe "#close" do
    before { client.start }

    it "closes the client" do
      client.close

      expect(client).not_to be_started
    end
  end

  describe "#wait_until_open" do
    it "waits until the client is open" do
      client.start
      expect { client.wait_until_open(timeout: 5) }.not_to raise_error
    end

    it "raises an error if the client is not open" do
      expect { client.wait_until_open(timeout: 0.5) }.to raise_error(Bidi2pdf::WebsocketError)
    end
  end

  describe "#send_cmd_and_wait" do
    context "when the client is started" do
      before do
        client.start
        client.wait_until_open
      end

      it "sends a command and waits for a response" do
        cmd.cmd = "session.status"
        response = client.send_cmd_and_wait(cmd, timeout: 5)

        expect(response).to include("type" => "success")
      end

      it "raises an error if the command is invalid" do
        cmd.cmd = "invalid"
        expect { client.send_cmd_and_wait(cmd, timeout: 5) }.to raise_error(Bidi2pdf::CmdError, /unknown command/)
      end

      it "raises an error when the timeout period elapses" do
        cmd.cmd = "session.status"
        expect { client.send_cmd_and_wait(cmd, timeout: 0) }.to raise_error(Bidi2pdf::CmdTimeoutError)
      end
    end

    context "when the client is not started" do
      it "raises an error if the client is not open" do
        cmd.cmd = "session.status"
        expect { client.send_cmd_and_wait(cmd, timeout: 0.5) }.to raise_error(Bidi2pdf::ClientError, /start must be called before/)
      end
    end
  end
end
