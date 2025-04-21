# frozen_string_literal: true

require "pdf-reader"
require "base64"

# RSpec matcher to assert the number of pages in a PDF document.
#
# This matcher is useful for verifying the structural integrity of generated or uploaded PDFs,
# especially in tests for reporting, invoice generation, or document exports.
#
# It supports a variety of input types:
# - Raw PDF data as a `String`
# - File paths (`String`)
# - `StringIO` or `File` objects
# - Even Base64-encoded strings, if your `pdf_reader_for` method handles it
#
# ## Example
#
#     expect(pdf_data).to have_pdf_page_count(5)
#     expect(StringIO.new(pdf_data)).to have_pdf_page_count(3)
#
# If the PDF is malformed, the matcher will gracefully fail and show the error message.
#
# @param expected_count [Integer] The number of pages the PDF is expected to contain.
# @return [RSpec::Matchers::Matcher] The matcher object for use in specs.
#
# @note This matcher depends on `Bidi2pdf::TestHelpers::PDFReaderUtils.pdf_reader_for`
#   to extract the page count. Make sure it supports all your intended input formats.
RSpec::Matchers.define :have_pdf_page_count do |expected_count|
  match do |pdf_data|
    reader = Bidi2pdf::TestHelpers::PDFReaderUtils.pdf_reader_for(pdf_data)
    @actual_count = reader.page_count
    @actual_count == expected_count
  rescue PDF::Reader::MalformedPDFError => e
    @error_message = e.message
    false
  end

  failure_message do |_pdf_data|
    if @error_message
      "Expected a valid PDF with #{expected_count} pages, but encountered an error: #{@error_message}"
    else
      "Expected PDF to have #{expected_count} pages, but it has #{@actual_count} pages"
    end
  end

  description do
    "have #{expected_count} PDF pages"
  end
end
