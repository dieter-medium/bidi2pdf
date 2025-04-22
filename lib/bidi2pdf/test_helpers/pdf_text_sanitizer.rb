# frozen_string_literal: true

require "unicode_utils"
require "diff/lcs"
require "diff/lcs/hunk"

module Bidi2pdf
  # rubocop: disable  Metrics/ModuleLength
  module TestHelpers
    # Provides utilities for sanitizing and comparing PDF text content.
    # This module includes methods for cleaning text, comparing PDF content,
    # and reporting differences between actual and expected PDF outputs.
    #
    # The sanitization process includes normalizing whitespace, replacing
    # typographic ligatures, and handling other common text formatting issues.
    #
    # @example Cleaning text
    #   sanitized_text = Bidi2pdf::TestHelpers::PDFTextSanitizer.clean("Some text")
    #
    # @example Comparing PDF content
    #   match = Bidi2pdf::TestHelpers::PDFTextSanitizer.match?(actual_pdf, expected_pdf)
    module PDFTextSanitizer
      class << self
        # Cleans the given text by replacing common typographic ligatures,
        # normalizing whitespace, and removing unnecessary characters.
        #
        # @param [String] text The text to clean.
        # @return [String] The cleaned text.
        def clean(text)
          text = UnicodeUtils.nfkd(text)

          text.gsub("\uFB01", "fi")
              .gsub("\uFB02", "fl")
              .gsub("-\n", "")
              .gsub(/["]/, '"')
              .gsub(/[']/, "'")
              .gsub("…", "...")
              .gsub("—", "--")
              .gsub("–", "-")
              .gsub(/\s+/, " ") # Replace all whitespace sequences with a single space
              .strip
        end

        # Cleans an array of PDF page texts by applying the `clean` method
        # to each page's content.
        #
        # @param [Object] actual_pdf_thingy The PDF object to clean.
        # @return [Array<String>] An array of cleaned page texts.
        def clean_pages(actual_pdf_thingy)
          Bidi2pdf::TestHelpers::PDFReaderUtils.pdf_text(actual_pdf_thingy).map { |text| clean(text) }
        end

        # Cleans the given text and removes all whitespace for comparison purposes.
        #
        # @param [String] text The text to clean and normalize.
        # @return [String] The cleaned text without whitespace.
        def clean_for_comparison(text)
          clean(text).gsub(/\s+/, "")
        end

        # Checks if the given PDF contains the expected text or pattern.
        #
        # @param [Object] actual_pdf_thingy The PDF object to search.
        # @param [String, Regexp] expected The expected text or pattern.
        # @param [Integer, nil] page_number The specific page to search (optional).
        # @return [Boolean] `true` if the expected text is found, `false` otherwise.
        def contains?(actual_pdf_thingy, expected, page_number = nil)
          pages = Bidi2pdf::TestHelpers::PDFReaderUtils.pdf_text(actual_pdf_thingy)
          cleaned_pages = clean_pages(pages)

          return false if page_number && page_number > cleaned_pages.size

          # Narrow to specific page if requested
          if page_number
            text = cleaned_pages[page_number - 1]
            return match_expected?(text, expected)
          end

          # Search all pages
          cleaned_pages.any? { |page| match_expected?(page, expected) }
        end

        # Matches the given text against the expected text or pattern.
        #
        # @param [String] text The text to match.
        # @param [String, Regexp] expected The expected text or pattern.
        # @return [Boolean] `true` if the text matches, `false` otherwise.
        def match_expected?(text, expected)
          return false unless text

          expected.is_a?(Regexp) ? text.match?(expected) : text.include?(expected.to_s)
        end

        # Compares the content of two PDF objects for equality.
        #
        # @param [Object] actual_pdf_thingy The actual PDF object.
        # @param [Object] expected_pdf_thingy The expected PDF object.
        # @return [Boolean] `true` if the content matches, `false` otherwise.
        def match?(actual_pdf_thingy, expected_pdf_thingy)
          actual = Bidi2pdf::TestHelpers::PDFReaderUtils.pdf_text actual_pdf_thingy
          expected = Bidi2pdf::TestHelpers::PDFReaderUtils.pdf_text expected_pdf_thingy

          cleaned_actual = clean_pages(actual)
          cleaned_expected = clean_pages(expected)

          # Compare without whitespace for equality check
          actual_for_comparison = cleaned_actual.map { |text| clean_for_comparison(text) }
          expected_for_comparison = cleaned_expected.map { |text| clean_for_comparison(text) }

          if actual_for_comparison == expected_for_comparison
            true
          else
            report_content_mismatch(cleaned_actual, cleaned_expected)
            false
          end
        end

        # Reports differences between actual and expected PDF content.
        #
        # @param [Array<String>] actual The actual PDF content.
        # @param [Array<String>] expected The expected PDF content.
        # @return [void]
        def report_content_mismatch(actual, expected)
          puts "--- PDF content mismatch ---"
          print_differences(actual, expected)
        end

        # Prints detailed differences between actual and expected PDF content.
        #
        # @param [Array<String>] actual The actual PDF content.
        # @param [Array<String>] expected The expected PDF content.
        # @return [void]
        def print_differences(actual, expected)
          max_pages = [actual.length, expected.length].max

          (0...max_pages).each do |page_idx|
            actual_page = actual[page_idx] || "(missing page)"
            expected_page = expected[page_idx] || "(missing page)"

            print_differences_for_page(actual_page, expected_page, page_idx)
          end
        end

        # Prints the differences between actual and expected content for a specific page.
        # This method compares the content ignoring whitespace and, if differences are found,
        # outputs a formatted representation of those differences.
        #
        # @param [String] actual_page The actual page content.
        # @param [String] expected_page The expected page content.
        # @param [Integer] page_idx The zero-based index of the page being compared.
        # @return [void]
        def print_differences_for_page(actual_page, expected_page, page_idx)
          # Compare without whitespace
          actual_no_space = clean_for_comparison(actual_page.to_s)
          expected_no_space = clean_for_comparison(expected_page.to_s)

          return if actual_no_space == expected_no_space

          puts "\nPage #{page_idx + 1} differences (ignoring whitespace):"

          # Create diffs between the two pages
          diffs = Diff::LCS.sdiff(expected_page, actual_page)

          # Format and display the differences
          puts format_diff_output(diffs, expected_page, actual_page)
        end

        # Formats the output of differences for display.
        #
        # @param [Array<Diff::LCS::ContextChange>] diffs The list of differences.
        # @param [String] expected The expected text.
        # @param [String] actual The actual text.
        # @return [String] The formatted differences.
        def format_diff_output(diffs, expected, actual)
          output = []

          # Find contiguous regions of changes
          changes = []
          current_change = nil

          diffs.each do |diff|
            case diff.action
            when "!", "+", "-" # Changed, added or deleted
              if current_change
                current_change[:diffs] << diff
              else
                current_change = { diffs: [diff] }
              end
            when "=" # Unchanged
              if current_change
                changes << current_change
                current_change = nil
              end
            end
          end
          changes << current_change if current_change

          # Output each change with context
          changes.each do |change|
            # Get the position
            pos = change[:diffs].first.old_position
            context_start = [0, pos - 20].max
            [expected.length, pos + 20].min

            # Format the output with context
            output << "  Context: ...#{expected[context_start...pos]}"

            # Show the differences
            expected_snippet = expected[pos, 50]
            actual_snippet = actual[change[:diffs].first.new_position, 50]
            output << "  Expected: #{expected_snippet}..."
            output << "  Actual:   #{actual_snippet}..."

            # Show normalized comparison
            output << "  Expected (no spaces): #{clean_for_comparison(expected_snippet)}..."
            output << "  Actual (no spaces):   #{clean_for_comparison(actual_snippet)}..."
          end

          output.join("\n")
        end
      end
    end
  end
  # rubocop: enable  Metrics/ModuleLength
end
