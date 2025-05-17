# frozen_string_literal: true

module Bidi2pdf
  module TestHelpers
    module Images
      require "vips"
      require "zlib"

      class Extractor
        include PDFReaderUtils
        include TIFFHelper

        attr_reader :pages, :logger

        def initialize(pdf_data, logger: Bidi2pdf.logger)
          reader = pdf_reader_for pdf_data
          @pages = reader.pages
          @logger = logger
        end

        def all_images
          extracted_images.map { |images| images[:images] }.flatten
        end

        def image_on_page(page_number, image_number)
          images = images_on_page(page_number)
          return nil if images.empty? || image_number > images.size

          images[image_number - 1]
        end

        def images_on_page(page_number)
          extracted_images.find { |images| images[:page] == page_number }&.dig(:images) || []
        end

        private

        def extracted_images
          @extracted_images ||= @pages.each_with_index.with_object([]) do |(page, index), result|
            result << { page: index + 1, images: extract_images(page) }
          end
        end

        def extract_images(page)
          xobjects = page.xobjects
          return if xobjects.empty?

          xobjects.each_value.map do |stream|
            case stream.hash[:Subtype]
            when :Image
              process_image_stream(stream)
            when :Form
              extract_images(PDF::Reader::FormXObject.new(page, stream))
            end
          end.flatten
        end

        def process_image_stream(stream)
          filter = Array(stream.hash[:Filter]).first
          raw = extract_raw_image_data(stream, filter)

          return nil if raw.nil? || raw.empty?

          create_vips_image(raw, filter)
        end

        def extract_raw_image_data(stream, filter)
          case filter
          when :DCTDecode, :JPXDecode then stream.data
          when :CCITTFaxDecode then tiff_header_for_CCITT(stream.hash, stream.data)
          when :LZWDecode, :RunLengthDecode, :FlateDecode then handle_compressed_image(stream)
          else
            Bidi2pdf.logger.warn("Unsupported image filter '#{filter}'. Attempting to process raw data.")
            stream.data
          end
        rescue StandardError => e
          Bidi2pdf.logger.error("Error extracting raw image data with filter '#{filter}': #{e.message}")
          nil # Return nil to indicate failure
        end

        def handle_compressed_image(stream)
          hash = stream.hash
          data = stream.unfiltered_data

          header = tiff_header(hash, data)

          header + data
        end

        def create_vips_image(raw, filter)
          Vips::Image.new_from_buffer(raw, "", disc: true)
        rescue Vips::Error => e
          Bidi2pdf.logger.error("Error creating Vips image from buffer (filter: #{filter}): #{e.message}")
          nil # Return nil if Vips fails
        end
      end
    end
  end
end
