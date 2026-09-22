# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::PdfInspection do
  after { described_class.reset_for_testing! }

  describe ".available?" do
    it "is true in this suite, where pdf-reader is already loaded via the test helpers" do
      described_class.reset_for_testing!

      expect(described_class.available?).to be true
    end

    it "is false when pdf-reader cannot be required" do
      described_class.reset_for_testing!
      allow(described_class).to receive(:require).with("pdf-reader").and_raise(LoadError)

      expect(described_class.available?).to be false
    end

    it "memoizes the false result rather than retrying require on every call" do
      described_class.reset_for_testing!
      allow(described_class).to receive(:require).with("pdf-reader").and_raise(LoadError)

      described_class.available?
      described_class.available?

      expect(described_class).to have_received(:require).once
    end
  end

  describe ".page_count" do
    let(:pdf_bytes) { File.binread(fixture_file("sample.pdf")) }

    it "returns the real page count when available" do
      expect(described_class.page_count(pdf_bytes)).to be_a(Integer)
    end

    it "returns nil without bytes" do
      expect(described_class.page_count(nil)).to be_nil
    end

    it "returns nil when pdf-reader is unavailable" do
      described_class.reset_for_testing!
      allow(described_class).to receive(:require).with("pdf-reader").and_raise(LoadError)

      expect(described_class.page_count(pdf_bytes)).to be_nil
    end

    it "returns nil for malformed PDF bytes rather than raising" do
      expect(described_class.page_count("not a pdf")).to be_nil
    end
  end

  describe ".text" do
    let(:pdf_bytes) { File.binread(fixture_file("sample.pdf")) }

    it "returns extracted text when available" do
      expect(described_class.text(pdf_bytes)).to be_a(String)
    end

    it "returns nil without bytes" do
      expect(described_class.text(nil)).to be_nil
    end
  end
end
