# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::ErrorCodes do
  describe ".for" do
    it "maps documented subclasses to their documented codes" do
      {
        Bidi2pdf::MissingInputError.new => "MISSING_INPUT",
        Bidi2pdf::MultipleInputSourcesError.new => "MULTIPLE_INPUT_SOURCES",
        Bidi2pdf::EmptyInputError.new => "EMPTY_INPUT",
        Bidi2pdf::InvalidConfigError.new => "INVALID_CONFIG",
        Bidi2pdf::InvalidPrintOptionError.new => "INVALID_PRINT_OPTION",
        Bidi2pdf::InvalidRecipeError.new => "INVALID_RECIPE",
        Bidi2pdf::PdfInspectionUnavailableError.new => "PDF_INSPECTION_UNAVAILABLE",
        Bidi2pdf::SessionNotStartedError.new => "BROWSER_LAUNCH_FAILED",
        Bidi2pdf::CmdTimeoutError.new => "COMMAND_TIMEOUT",
        Bidi2pdf::WebsocketError.new => "BROWSER_DISCONNECTED",
        Bidi2pdf::NavigationTimeoutError.new => "NAVIGATION_TIMEOUT",
        Bidi2pdf::NavigationAuthError.new("http://x") => "NAVIGATION_AUTH",
        Bidi2pdf::NavigationNotFoundError.new => "NAVIGATION_NOT_FOUND",
        Bidi2pdf::NavigationDNSError.new => "DNS_ERROR",
        Bidi2pdf::NavigationError.new => "NAVIGATION_FAILED",
        Bidi2pdf::SelectorNotFoundError.new => "SELECTOR_NOT_FOUND",
        Bidi2pdf::PageNotAsExpectedError.new => "PAGE_NOT_AS_EXPECTED",
        Bidi2pdf::ScriptInjectionError.new => "SCRIPT_ERROR",
        Bidi2pdf::StyleInjectionError.new => "STYLE_ERROR",
        Bidi2pdf::PrintError.new => "PDF_GENERATION_FAILED",
        Bidi2pdf::ScreenshotError.new => "SCREENSHOT_FAILED",
        Bidi2pdf::OutputWriteError.new => "OUTPUT_WRITE_FAILED"
      }.each do |exception, expected_code|
        expect(described_class.for(exception)).to eq(expected_code), "expected #{exception.class} to map to #{expected_code}"
      end
    end

    it "checks the more specific subclass before its ancestor" do
      expect(described_class.for(Bidi2pdf::NavigationTimeoutError.new)).to eq("NAVIGATION_TIMEOUT")
    end

    it "still maps the ancestor on its own" do
      expect(described_class.for(Bidi2pdf::NavigationError.new)).to eq("NAVIGATION_FAILED")
    end

    it "falls back to INTERNAL_ERROR for a plain Bidi2pdf::Error" do
      expect(described_class.for(Bidi2pdf::Error.new)).to eq("INTERNAL_ERROR")
    end

    it "falls back to INTERNAL_ERROR for a non-Bidi2pdf exception" do
      expect(described_class.for(StandardError.new)).to eq("INTERNAL_ERROR")
    end
  end

  describe ".describe" do
    it "carries retryable and hint from the exception" do
      error = Bidi2pdf::NavigationTimeoutError.new("Navigation did not complete within 60 seconds")

      described = described_class.describe(error)

      expect(described).to eq(
        code: "NAVIGATION_TIMEOUT",
        message: "Navigation did not complete within 60 seconds",
        retryable: true,
        hint: error.hint,
        details: {}
      )
    end

    it "carries structured details set at raise time" do
      error = Bidi2pdf::SelectorNotFoundError.new("Selector '#total' was not found", details: { selector: "#total" })

      expect(described_class.describe(error)[:details]).to eq(selector: "#total")
    end

    it "defaults retryable/hint safely for a non-Bidi2pdf exception" do
      described = described_class.describe(StandardError.new("boom"))

      expect(described).to eq(code: "INTERNAL_ERROR", message: "boom", retryable: false, hint: nil, details: {})
    end

    it "falls back to the details: kwarg when the exception carries none" do
      described = described_class.describe(StandardError.new("boom"), details: { step: 2 })

      expect(described[:details]).to eq(step: 2)
    end
  end
end
