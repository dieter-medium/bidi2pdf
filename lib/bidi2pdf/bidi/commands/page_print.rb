# frozen_string_literal: true

require_relative "print_parameters_validator"

module Bidi2pdf
  module Bidi
    module Commands
      class PagePrint
        include Base

        def initialize(cdp_session:, print_options:)
          @cdp_session = cdp_session
          @print_options = print_options || { background: true }

          PrintParametersValidator.validate!(@print_options)

          return unless @print_options[:page]&.key?(:format)

          @print_options[:page] = Bidi2pdf.translate_paper_format @print_options[:page][:format]
        end

        # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        def params
          {
            # https://chromedevtools.github.io/devtools-protocol/tot/Page/#method-printToPDF
            method: "Page.printToPDF",
            session: @cdp_session,
            params: {
              "printBackground" => @print_options[:background],

              "marginTop" => cm_to_inch(@print_options.dig(:margin, :top) || 0),
              "marginBottom" => cm_to_inch(@print_options.dig(:margin, :bottom) || 0),
              "marginLeft" => cm_to_inch(@print_options.dig(:margin, :left) || 0),
              "marginRight" => cm_to_inch(@print_options.dig(:margin, :right) || 0),
              "landscape" => (@print_options[:orientation] || "portrait").to_sym == :landscape,

              "paperWidth" => cm_to_inch(@print_options.dig(:page, :width)),
              "paperHeight" => cm_to_inch(@print_options.dig(:page, :height)),
              "pageRanges" => page_ranges_to_string(@print_options[:pageRanges]),
              "scale" => @print_options[:scale] || 1.0,

              "displayHeaderFooter" => @print_options[:display_header_footer],
              "headerTemplate" => @print_options[:header_template] || "",
              "footerTemplate" => @print_options[:footer_template] || "",

              "preferCSSPageSize" => @print_options.fetch(:prefer_css_page_size, true),

              "generateTaggedPDF" => @print_options.fetch(:generate_tagged_pdf, false),
              "generateDocumentOutline" => @print_options.fetch(:generate_document_outline, false),

              transferMode: "ReturnAsBase64"
            }.compact
          }
        end

        # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

        def method_name
          "goog:cdp.sendCommand"
        end

        private

        # rubocop:disable  Naming/MethodParameterName
        def cm_to_inch(cm)
          return nil if cm.nil?

          cm.to_f / 2.54
        end

        # rubocop:enable  Naming/MethodParameterName

        # rubocop:disable Metrics/CyclomaticComplexity
        def page_ranges_to_string(input)
          return nil if input.nil? || input.empty?

          segments = input.map do |entry|
            case entry
            when Integer
              entry.to_s
            when String
              raise ArgumentError, "Invalid page entry: #{entry.inspect}" unless entry =~ /\A\d+(-\d+)?\z/

              entry
            else
              raise ArgumentError, "Unsupported page entry type: #{entry.class}"
            end
          end

          # dedupe, sort by numeric start, and join
          segments
            .uniq
            .sort_by { |seg| seg.split("-", 2).first.to_i }
            .join(",")
        end

        # rubocop:enable Metrics/CyclomaticComplexity
      end
    end
  end
end
