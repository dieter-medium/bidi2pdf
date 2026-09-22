# frozen_string_literal: true

require "stringio"

module Bidi2pdf
  # Lazy, optional wrapper around the pdf-reader gem. pdf-reader is deliberately NOT a bidi2pdf
  # runtime dependency - render works fine without it,
  # just with `pages` left nil and a warning, and a recipe assertion that needs it fails
  # INVALID_RECIPE at validation time rather than crashing mid-render. The official Docker images
  # (docker/Dockerfile, docker/Dockerfile.slim) install it, so a render inside one of them - the
  # environment an agent or CI job actually uses - always has page counts and PDF assertions
  # available without anyone opting in by hand.
  module PdfInspection
    class << self
      def available?
        return @available if defined?(@available)

        @available = load_pdf_reader
      end

      # @param bytes [String, nil] raw PDF bytes.
      # @return [Integer, nil] page count, or nil when pdf-reader is unavailable, bytes is nil,
      #   or the PDF is malformed.
      def page_count(bytes)
        return nil unless bytes && available?

        reader_for(bytes).page_count
      rescue PDF::Reader::MalformedPDFError
        nil
      end

      # @param bytes [String, nil] raw PDF bytes.
      # @return [String, nil] extracted text across all pages, joined with newlines.
      def text(bytes)
        return nil unless bytes && available?

        reader_for(bytes).pages.map(&:text).join("\n")
      rescue PDF::Reader::MalformedPDFError
        nil
      end

      # Clears the memoized availability check - test-only, so a spec can exercise both branches
      # of #available? regardless of load order elsewhere in the process.
      def reset_for_testing!
        remove_instance_variable(:@available) if defined?(@available)
      end

      private

      def load_pdf_reader
        require "pdf-reader"
        true
      rescue LoadError
        false
      end

      def reader_for(bytes)
        PDF::Reader.new(StringIO.new(bytes))
      end
    end
  end
end
