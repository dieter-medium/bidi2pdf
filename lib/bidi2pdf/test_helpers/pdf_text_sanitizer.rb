# frozen_string_literal: true

require "unicode_utils"
require "diff/lcs"
require "diff/lcs/hunk"

module Bidi2pdf
  module TestHelpers
    # rubocop: disable Metrics/ModuleLength
    module PDFTextSanitizer
      class << self
        def clean(text)
          text = UnicodeUtils.nfkd(text)

          text.gsub("\uFB01", "fi")
              .gsub("\uFB02", "fl")
              .gsub("-\n", "")
              .gsub('"', '"')
              .gsub("'", "'")
              .gsub("…", "...")
              .gsub("—", "--")
              .gsub("–", "-")
              .gsub(/\s+/, " ")
              .strip
        end

        def clean_pages(pdf)
          Bidi2pdf::TestHelpers::PDFReaderUtils.pdf_text(pdf).map { |text| clean(text) }
        end

        def normalize(text)
          clean(text).gsub(/\s+/, "")
        end

        def contains?(actual_pdf_thingy, expected, page_number = nil)
          cleaned_pages = clean_pages(actual_pdf_thingy)

          return false if page_number && page_number > cleaned_pages.size

          if page_number
            text = cleaned_pages[page_number - 1]
            return match_expected?(text, expected)
          end

          cleaned_pages.any? { |page| match_expected?(page, expected) }
        end

        def match_expected?(text, expected)
          return false unless text

          expected.is_a?(Regexp) ? text.match?(expected) : text.include?(expected.to_s)
        end

        def match?(actual_pdf_thingy, expected_pdf_thingy)
          cleaned_actual = clean_pages(actual_pdf_thingy)
          cleaned_expected = clean_pages(expected_pdf_thingy)

          actual_for_comparison = cleaned_actual.map { |text| normalize(text) }
          expected_for_comparison = cleaned_expected.map { |text| normalize(text) }

          return true if actual_for_comparison == expected_for_comparison

          report_content_mismatch(cleaned_actual, cleaned_expected)
          false
        end

        def report_content_mismatch(actual, expected)
          reporter.message(content_mismatch_message(actual, expected))
        end

        def content_mismatch_message(actual, expected)
          sections = ["--- PDF content mismatch ---"]
          max_pages = [actual.length, expected.length].max

          (0...max_pages).each do |page_idx|
            actual_page = actual[page_idx] || "(missing page)"
            expected_page = expected[page_idx] || "(missing page)"

            page_message = page_difference_message(actual_page, expected_page, page_idx)
            sections << page_message if page_message
          end

          sections.join("\n")
        end

        def page_difference_message(actual_page, expected_page, page_idx)
          actual_no_space = normalize(actual_page.to_s)
          expected_no_space = normalize(expected_page.to_s)

          return nil if actual_no_space == expected_no_space

          diffs = Diff::LCS.sdiff(expected_page, actual_page)

          [
            "",
            "Page #{page_idx + 1} differences (ignoring whitespace):",
            format_diff_output(diffs, expected_page, actual_page)
          ].join("\n")
        end

        def format_diff_output(diffs, expected, actual)
          changes = group_changed_diffs(diffs)

          changes.flat_map { |change| format_change(expected, actual, change) }.join("\n")
        end

        def reporter
          RSpec.configuration.reporter
        end

        private

        def group_changed_diffs(diffs)
          diffs
            .chunk_while { |_prev, curr| curr.action != "=" }
            .map { |chunk| chunk.reject { |elem| elem.action == "=" } }
            .select(&:any?)
            .map { |chunk| { diffs: chunk } }
        end

        def format_change(expected, actual, change)
          pos = change[:diffs].first.old_position
          snippets = extract_snippets(expected, actual, change, pos)

          build_output(snippets, pos)
        end

        def extract_snippets(expected, actual, change, pos)
          {
            context_start: [0, pos - 20].max,
            context: expected,
            expected_snip: expected[pos, 50],
            actual_snip: actual[change[:diffs].first.new_position, 50]
          }
        end

        def build_output(snip_data, pos)
          start = snip_data[:context_start]
          ctx = snip_data[:context]

          [
            "  Context: ...#{ctx[start...pos]}",
            "  Expected: #{snip_data[:expected_snip]}...",
            "  Actual:   #{snip_data[:actual_snip]}...",
            "  Expected (no spaces): #{normalize(snip_data[:expected_snip])}...",
            "  Actual (no spaces):   #{normalize(snip_data[:actual_snip])}..."
          ]
        end
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
