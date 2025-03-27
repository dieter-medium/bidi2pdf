# frozen_string_literal: true

require_relative "../pdf_text_sanitizer"

RSpec::Matchers.define :match_pdf_text do |expected|
  match do |actual|
    PDFTextSanitizer.match?(actual, expected)
  end

  failure_message do |actual|
    cleaned_actual = PDFTextSanitizer.clean_pages(actual)
    cleaned_expected = PDFTextSanitizer.clean_pages(expected)

    <<~MSG
      PDF text did not match.

      --- Expected ---
      #{cleaned_expected.join("\n")}

      --- Actual ---
      #{cleaned_actual.join("\n")}
    MSG
  end

  description do
    "match sanitized PDF text content"
  end
end
