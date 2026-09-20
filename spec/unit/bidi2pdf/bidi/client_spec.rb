# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::Bidi::Client do
  subject(:client) { described_class.new("ws://example.com/socket") }

  describe "#open?" do
    it "is false before the client has started" do
      expect(client).not_to be_open
    end

    it "reflects the underlying socket's own #open? once connected" do
      socket = instance_double(Bidi2pdf::Bidi::BufferedWebSocketClient, open?: true)
      client.instance_variable_set(:@socket, socket)

      expect(client).to be_open
    end

    it "is false once the underlying socket reports itself closed" do
      socket = instance_double(Bidi2pdf::Bidi::BufferedWebSocketClient, open?: false)
      client.instance_variable_set(:@socket, socket)

      expect(client).not_to be_open
    end
  end
end
