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

    it "reports the real byte size, not the character count, for multi-byte UTF-8 content" do
      value = "ä" * 500 # 2 bytes/char in UTF-8 - byte count differs from character count

      result = described_class.truncate_for_log(value, limit: 1000)

      expect(result).to eq(value)
      expect("ä" * 500).to eq(value)
      expect(value.length).to eq(500)
      expect(value.bytesize).to eq(1000)
    end

    it "truncates multi-byte UTF-8 content at a valid character boundary and reports the real byte size" do
      value = "€" * 500 # 3 bytes/char in UTF-8; 1500 bytes total, not evenly divisible by the 200-byte limit

      result = described_class.truncate_for_log(value)

      expect(result).to eq("#{"€" * 66}... (1500 bytes total)")
      expect(result).to be_valid_encoding
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
