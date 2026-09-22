# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::Result do
  describe ".success" do
    it "is ok?" do
      expect(described_class.success(command: "render")).to be_ok
    end

    it "serializes to the documented key order, with error always present as nil" do
      result = described_class.success(command: "render", output: "out.pdf", bytes: 10, sha256: "abc", pages: 1,
                                       duration_ms: 5, navigation: { requested_url: "http://x" })

      expect(result.to_h).to eq(
        schema_version: 1,
        ok: true,
        command: "render",
        output: "out.pdf",
        bytes: 10,
        sha256: "abc",
        pages: 1,
        duration_ms: 5,
        navigation: { requested_url: "http://x" },
        console: [],
        network_failures: [],
        warnings: [],
        error: nil
      )
    end
  end

  describe ".failure" do
    it "is not ok?" do
      expect(described_class.failure(command: "render", error: {})).not_to be_ok
    end

    it "carries the error hash" do
      error = { code: "NAVIGATION_TIMEOUT", message: "timed out", retryable: true, hint: "raise the timeout", details: {} }

      expect(described_class.failure(command: "render", error: error).error).to eq(error)
    end
  end

  describe "#to_h" do
    it "omits metadata when empty" do
      expect(described_class.success(command: "render").to_h).not_to have_key(:metadata)
    end

    it "includes metadata when present" do
      result = described_class.success(command: "render", metadata: { recipe: "x.yml" })

      expect(result.to_h[:metadata]).to eq(recipe: "x.yml")
    end
  end

  describe "#to_json" do
    it "serializes to the same shape as #to_h" do
      result = described_class.success(command: "version")

      expect(JSON.parse(result.to_json, symbolize_names: true)).to eq(result.to_h)
    end
  end
end
