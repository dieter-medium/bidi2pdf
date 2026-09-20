# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf do
  it "has a version number" do
    expect(described_class::VERSION).not_to be_nil
  end

  describe ".truncate_for_log" do
    it "returns a short value unchanged" do
      expect(described_class.truncate_for_log("short")).to eq("short")
    end

    it "returns a value exactly at the limit unchanged" do
      value = "x" * 200

      expect(described_class.truncate_for_log(value)).to eq(value)
    end

    it "truncates a value over the limit and appends a byte-count marker" do
      value = "x" * 500

      result = described_class.truncate_for_log(value)

      expect(result).to eq("#{"x" * 200}... (500 bytes total)")
    end

    it "honors a custom limit" do
      value = "x" * 50

      expect(described_class.truncate_for_log(value, limit: 10)).to eq("#{"x" * 10}... (50 bytes total)")
    end

    it "defaults to Bidi2pdf.log_truncate_limit, so it's configurable without passing limit: everywhere" do
      old_limit = described_class.log_truncate_limit
      described_class.log_truncate_limit = 10
      value = "x" * 50

      expect(described_class.truncate_for_log(value)).to eq("#{"x" * 10}... (50 bytes total)")
    ensure
      described_class.log_truncate_limit = old_limit
    end
  end
end
