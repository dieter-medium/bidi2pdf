# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::Bidi::NetworkEvent do
  subject(:event) do
    described_class.new(
      id: "req-1", url: "https://example.com", timestamp: 1000.0, timing: nil,
      state: "network.beforeRequestSent", navigation: "nav-1"
    )
  end

  describe "#navigation" do
    it "exposes the navigation id it was created with" do
      expect(event.navigation).to eq("nav-1")
    end

    it "generates a value for a request unrelated to any navigation (a sub-resource fetch)" do
      sub_resource = described_class.new(id: "req-2", url: "https://example.com/logo.png", timestamp: 1000.0, timing: nil, state: "network.beforeRequestSent")

      expect(sub_resource.navigation).not_to be_nil
    end

    it "generates a distinct value per instance, so unrelated sub-resource fetches stay distinguishable" do
      first = described_class.new(id: "req-2", url: "https://example.com/logo.png", timestamp: 1000.0, timing: nil, state: "network.beforeRequestSent")
      second = described_class.new(id: "req-3", url: "https://example.com/style.css", timestamp: 1000.0, timing: nil, state: "network.beforeRequestSent")

      expect(first.navigation).not_to eq(second.navigation)
    end
  end

  describe "#dup" do
    it "carries the navigation id over" do
      expect(event.dup.navigation).to eq("nav-1")
    end
  end

  describe "#to_s" do
    it "includes the navigation id" do
      expect(event.to_s).to include("navigation=\"nav-1\"")
    end
  end
end
