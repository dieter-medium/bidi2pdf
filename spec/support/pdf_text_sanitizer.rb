# frozen_string_literal: true

require "unicode_utils"
require "diff/lcs"
require "diff/lcs/hunk"

# rubocop: disable all
module PDFTextSanitizer
  # Replaces common typographic ligatures and normalizes whitespace
  def self.clean(text)
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

  # Cleans an array of PDF page texts
  def self.clean_pages(pages)
    pages.map { |text| clean(text) }
  end

  # For comparison, remove all whitespace
  def self.clean_for_comparison(text)
    clean(text).gsub(/\s+/, "")
  end

  # Compares two sets of PDF texts safely
  def self.match?(actual, expected)
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

  def self.report_content_mismatch(actual, expected)
    puts "--- PDF content mismatch ---"
    print_differences(actual, expected)
  end

  def self.print_differences(actual, expected)
    max_pages = [actual.length, expected.length].max

    (0...max_pages).each do |page_idx|
      actual_page = actual[page_idx] || "(missing page)"
      expected_page = expected[page_idx] || "(missing page)"

      # Compare without whitespace
      actual_no_space = clean_for_comparison(actual_page.to_s)
      expected_no_space = clean_for_comparison(expected_page.to_s)

      next if actual_no_space == expected_no_space

      puts "\nPage #{page_idx + 1} differences (ignoring whitespace):"

      # Create diffs between the two pages
      diffs = Diff::LCS.sdiff(expected_page, actual_page)

      # Format and display the differences
      puts format_diff_output(diffs, expected_page, actual_page)
    end
  end

  def self.format_diff_output(diffs, expected, actual)
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
# rubocop: enable all
