# frozen_string_literal: true

RSpec.describe Bidi2pdf::TestHelpers::PDFTextSanitizer do

  describe ".clean" do
    it "cleans the text by replacing ligatures and normalizing whitespace" do
      input_text = "Some \uFB01\ntext with \uFB02\nligatures and   extra spaces."
      expected_output = "Some fi text with fl ligatures and extra spaces."
      expect(described_class.clean(input_text)).to eq(expected_output)
    end
  end

  describe ".clean_pages" do
    it "cleans an array of PDF page texts" do
      pdf_texts = ["Some \uFB01\ntext", "with \uFB02\nligatures"]
      expected_output = ["Some fi text", "with fl ligatures"]
      expect(described_class.clean_pages(pdf_texts)).to eq(expected_output)
    end
  end

  describe ".clean_for_comparison" do
    it "cleans the text and removes all whitespace" do
      input_text = "Some \uFB01\ntext with \uFB02\nligatures and   extra spaces."
      expected_output = "Somefitextwithflligaturesandextraspaces."
      expect(described_class.clean_for_comparison(input_text)).to eq(expected_output)
    end
  end

  describe ".contains?" do
    let(:pdf_file) { fixture_file("sample.pdf") }

    it "checks if the PDF contains the expected text" do
      expected_text = "Section Two (New Page)"
      expect(described_class.contains?(pdf_file, expected_text)).to be_truthy
    end

    it "checks if the PDF contains the expected text on a specific page" do
      expected_text = "Section Two (New Page)"
      expect(described_class.contains?(pdf_file, expected_text, 2)).to be_truthy
    end

    it "returns false if the expected text is not found" do
      expected_text = "Section Two does not exists (New Page)"
      expect(described_class.contains?(pdf_file, expected_text)).to be_falsey
    end

    it "returns false if the page number is out of range" do
      expected_text = "Section Two (New Page)"
      expect(described_class.contains?(pdf_file, expected_text, 999)).to be_falsey
    end

    it "returns false, when the expected text is not found within the page" do
      expected_text = "Section Two (New Page)"
      expect(described_class.contains?(pdf_file, expected_text, 1)).to be_falsey
    end
  end

  describe ".match_expected?" do
    it "matches the expected text" do
      text = "Some text with ligatures"
      expected = /text with ligatures/
      expect(described_class.match_expected?(text, expected)).to be_truthy
    end

    it "does not match when the expected text is not found" do
      text = "Some other text"
      expected = /text with ligatures/
      expect(described_class.match_expected?(text, expected)).to be_falsey
    end

    it "matches when the expected text is a string" do
      text = "Some text with ligatures"
      expected = "text with ligatures"
      expect(described_class.match_expected?(text, expected)).to be_truthy
    end

    it "does not match when the expected text is a string but not found" do
      text = "Some other text"
      expected = "text with ligatures"
      expect(described_class.match_expected?(text, expected)).to be_falsey
    end
  end

  describe ".match?" do
    let(:actual_pdf_thingy) { fixture_file("sample.pdf") }
    let(:expected_pdf_thingy) { fixture_file("expected.pdf") }

    it "matches the content of two PDF objects" do
      expect(described_class.match?(actual_pdf_thingy, expected_pdf_thingy)).to be_truthy
    end

    it "does not match when the content is different" do
      expect(described_class.match?(actual_pdf_thingy, fixture_file("different.pdf"))).to be_falsey
    end

    it "reports content mismatch when the content is different" do
      expect { described_class.match?(actual_pdf_thingy, fixture_file("different.pdf")) }.to output(/PDF content mismatch/).to_stdout
    end
  end

  describe ".report_content_mismatch" do
    it "prints a message indicating the content mismatch" do
      cleaned_actual = ["Some fi text", "with fl ligatures"]
      cleaned_expected = ["Some text", "with ligatures"]

      expect { described_class.report_content_mismatch(cleaned_actual, cleaned_expected) }.to output(/Page 1 differences \(ignoring whitespace\).*Page 2 differences \(ignoring whitespace\)/m).to_stdout
    end
  end
end