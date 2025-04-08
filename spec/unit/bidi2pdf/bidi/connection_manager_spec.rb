# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::Bidi::ConnectionManager do
  subject(:connection_manager) { described_class.new logger: logger }

  let(:logger) { Logger.new($stdout) }

  describe "#wait_until_open" do
    it "waits until the connection is open" do
      # Start the wait in a separate thread
      waiting_thread = Thread.new do
        expect { connection_manager.wait_until_open(timeout: 1) }.not_to raise_error
      end

      sleep 0.1

      connection_manager.mark_connected

      waiting_thread.join
    end

    it "raises an error if the connection is not open" do
      expect { connection_manager.wait_until_open(timeout: 0.1) }.to raise_error(Bidi2pdf::WebsocketError)
    end
  end
end
