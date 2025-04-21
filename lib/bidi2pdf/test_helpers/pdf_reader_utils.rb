# frozen_string_literal: true

module Bidi2pdf
  module TestHelpers
    module PDFReaderUtils
      class << self
        # Extracts text content from a PDF document.
        #
        # This method accepts various PDF input formats and attempts to extract text content
        # from all pages. If extraction fails due to malformed PDF data, it returns the original input.
        #
        # @param pdf_data [String, StringIO, File] The PDF data in one of the following formats:
        #   * Base64-encoded PDF string
        #   * Raw PDF data beginning with "%PDF-"
        #   * StringIO object containing PDF data
        #   * Path to a PDF file as String
        #   * Raw PDF data as String
        # @return [Array<String>] An array of strings, with each string representing the text content of a page
        # @return [Object] The original input if PDF extraction fails
        # @example Extract text from a PDF file
        #   text_content = pdf_text('path/to/document.pdf')
        #
        # @example Extract text from Base64-encoded string
        #   text_content = pdf_text(base64_encoded_pdf_data)
        def pdf_text(pdf_data)
          return pdf_data unless pdf_data.is_a?(String) || pdf_data.is_a?(StringIO) || pdf_data.is_a?(File)

          begin
            reader = pdf_reader_for pdf_data
            reader.pages.map(&:text)
          rescue PDF::Reader::MalformedPDFError
            [pdf_data]
          end
        end

        # Converts the input PDF data into an IO object and initializes a PDF::Reader.
        #
        # @param pdf_data [String, StringIO, File] The PDF data to be read.
        # @return [PDF::Reader] A PDF::Reader instance for the given data.
        # @raise [PDF::Reader::MalformedPDFError] If the PDF data is invalid.
        def pdf_reader_for(pdf_data)
          io = convert_data_to_io(pdf_data)
          PDF::Reader.new(io)
        end

        # rubocop: disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        # Converts various input formats into an IO object for PDF::Reader.
        #
        # @param pdf_data [String, StringIO, File] The PDF data to be converted.
        # @return [IO] An IO object containing the PDF data.
        def convert_data_to_io(pdf_data)
          # rubocop:disable Lint/DuplicateBranch
          if pdf_data.is_a?(String) && (pdf_data.start_with?("JVBERi") || pdf_data.start_with?("JVBER"))
            StringIO.new(Base64.decode64(pdf_data))
          elsif pdf_data.start_with?("%PDF-")
            StringIO.new(pdf_data)
          elsif pdf_data.is_a?(StringIO)
            pdf_data
          elsif pdf_data.is_a?(String) && File.exist?(pdf_data)
            File.open(pdf_data, "rb")
          else
            StringIO.new(pdf_data)
          end
          # rubocop:enable Lint/DuplicateBranch
        end
      end

      # rubocop: enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      module InstanceMethods
        def pdf_text(pdf_data)
          PDFReaderUtils.pdf_text(pdf_data)
        end

        def pdf_reader_for(pdf_data)
          PDFReaderUtils.pdf_reader_for(pdf_data)
        end

        def convert_data_to_io(pdf_data)
          PDFReaderUtils.convert_data_to_io(pdf_data)
        end
      end

      def self.included(base)
        base.include(InstanceMethods)
      end
    end
  end
end
