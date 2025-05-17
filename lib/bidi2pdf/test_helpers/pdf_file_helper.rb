# frozen_string_literal: true

module Bidi2pdf
  module TestHelpers
    # This module provides helper methods for handling PDF files in tests.
    # It includes methods for debugging, storing, and managing PDF files.
    module PdfFileHelper
      # Executes a block with the given PDF data and handles debugging in case of test failures.
      # If an expectation fails, the PDF data is saved to a file for debugging purposes.
      # @param [String] pdf_data the PDF data to debug
      # @yield [String] yields the PDF data to the given block
      # @raise [RSpec::Expectations::ExpectationNotMetError] re-raises the exception after saving the PDF
      def with_pdf_debug(pdf_data)
        yield pdf_data
      rescue RSpec::Expectations::ExpectationNotMetError => e
        failure_output = store_pdf_file pdf_data, "test-failure"
        puts "Test failed! PDF saved to: #{failure_output}"
        raise e
      end

      # Stores the given PDF data to a file with a specified filename prefix.
      # The file is saved in a temporary directory.
      # @param [String] pdf_data the PDF data to store
      # @param [String] filename_prefix the prefix for the generated filename (default: "test")
      # @return [String] the full path to the saved PDF file
      def store_pdf_file(pdf_data, filename_prefix = "test")
        pdf_file = tmp_file("pdf-files", "#{filename_prefix}-#{Time.now.to_i}.pdf")
        FileUtils.mkdir_p(File.dirname(pdf_file))
        File.binwrite(pdf_file, pdf_data)

        pdf_file
      end
    end

    RSpec.configure do |config|
      config.include PdfFileHelper, pdf: true
    end
  end
end
