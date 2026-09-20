# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::Bidi::NetworkEvents do
  subject(:network_events) { described_class.new(context_id) }

  let(:context_id) { "ctx-1" }

  describe "#handle_response" do
    it "captures the navigation id from network.beforeRequestSent" do
      network_events.handle_event(
        "method" => "network.beforeRequestSent",
        "params" => {
          "context" => context_id,
          "navigation" => "nav-1",
          "timestamp" => 1000,
          "request" => { "request" => "req-1", "url" => "https://example.com", "method" => "GET", "timings" => nil }
        }
      )

      expect(network_events.events["req-1"].navigation).to eq("nav-1")
    end

    it "leaves navigation nil for a request with no navigation field (a sub-resource fetch)" do
      network_events.handle_event(
        "method" => "network.beforeRequestSent",
        "params" => {
          "context" => context_id,
          "timestamp" => 1000,
          "request" => { "request" => "req-2", "url" => "https://example.com/logo.png", "method" => "GET", "timings" => nil }
        }
      )

      expect(network_events.events["req-2"].navigation).to be_nil
    end
  end
end
