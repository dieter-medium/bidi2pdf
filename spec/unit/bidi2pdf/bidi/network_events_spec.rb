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

  describe "#wait_until_network_idle" do
    # A request whose response started but never completed - a page that keeps polling.
    def start_request(id)
      request = { "request" => id, "url" => "https://example.com/poll", "method" => "GET", "timings" => nil }
      network_events.handle_event("method" => "network.beforeRequestSent",
                                  "params" => { "context" => context_id, "timestamp" => 1000, "request" => request })
      network_events.handle_event("method" => "network.responseStarted",
                                  "params" => { "context" => context_id, "timestamp" => 1001, "request" => request,
                                                "response" => { "status" => 200 } })
    end

    it "says it timed out, without raising, while a request is still open" do
      start_request("req-open")

      expect(network_events.wait_until_network_idle(timeout: 0.05, poll_interval: 0.01)).to eq(:timeout)
    end

    it "says the network went idle when nothing is open" do
      expect(network_events.wait_until_network_idle(timeout: 0.05, poll_interval: 0.01)).to eq(:idle)
    end

    it "names the open requests when it gives up" do
      start_request("req-open")
      allow(Bidi2pdf.logger).to receive(:warn)

      network_events.wait_until_network_idle(timeout: 0.05, poll_interval: 0.01)

      expect(Bidi2pdf.logger).to have_received(:warn).with(a_string_including("req-open"))
    end
  end
end
