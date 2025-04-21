# frozen_string_literal: true

require_relative "../pdf_text_sanitizer"

# Custom RSpec matcher for checking whether a PDF document contains specific text.
#
# This matcher allows you to assert that a certain string or regular expression
# is present in the sanitized text of a PDF document.
#
# It supports chaining with `.at_page(n)` to limit the search to a specific page.
#
# ## Examples
#
#     expect(pdf_data).to contains_pdf_text("Total: 123.45")
#     expect(pdf_data).to contains_pdf_text(/Invoice #\d+/).at_page(2)
#
# @param expected [String, Regexp] The text or pattern to match inside the PDF.
#
# @return [Boolean] true if the expected content is found (on the given page if specified)
RSpec::Matchers.define :contains_pdf_text do |expected|
  chain :at_page do |page_number|
    @page_number = page_number
  end

  match do |actual|
    PDFTextSanitizer.contains?(actual, expected, @page_number)
  end

  failure_message do |actual|
    pages = PDFTextSanitizer.clean_pages(actual)

    return "Document does not contain page #{@page_number}" if @page_number && !(@page_number && @page_number <= pages.size)

    <<~MSG
      PDF text did not contain expected content.

      --- Expected (#{expected.inspect}) ---
      On page #{@page_number || "any"}:

      --- Actual ---
      #{pages.each_with_index.map { |text, i| "Page #{i + 1}:\n#{text}" }.join("\n\n")}
    MSG
  end

  description do
    desc = "contain #{expected.inspect} in PDF"
    desc += " on page #{@page_number}" if @page_number
    desc
  end
end
