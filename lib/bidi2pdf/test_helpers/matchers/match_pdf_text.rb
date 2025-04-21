# frozen_string_literal: true

require_relative "../pdf_text_sanitizer"

# Custom RSpec matcher to compare the **sanitized text content** of two PDF files.
#
# This matcher is useful for comparing PDF documents where formatting and metadata may differ,
# but the actual visible text content should be the same. It uses `PDFTextSanitizer` internally
# to normalize and clean the text before comparison.
#
# ## Example
#
#     expect(actual_pdf).to match_pdf_text(expected_pdf)
#
# If the texts don’t match, it prints a diff-friendly message showing cleaned text content.
#
# @param expected [String, StringIO, File] The expected PDF content (can be a file path, StringIO, or raw string).
# @return [RSpec::Matchers::Matcher] An RSpec matcher to compare against an actual PDF.
#
# @note Ensure `PDFTextSanitizer.match?` and `PDFTextSanitizer.clean_pages` are implemented
#   to handle your specific PDF processing logic.
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
