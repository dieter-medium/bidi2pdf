# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module Commands
      # Validates parameters for the BiDi method `browsingContext.print`.
      #
      # Allowed structure of the params hash:
      #
      # {
      #   background: Boolean (optional, default: false) – print background graphics,
      #   margin: {
      #     top: Float >= 0.0 (optional, default: 1.0),
      #     bottom: Float >= 0.0 (optional, default: 1.0),
      #     left: Float >= 0.0 (optional, default: 1.0),
      #     right: Float >= 0.0 (optional, default: 1.0)
      #   },
      #   orientation: "portrait" or "landscape" (optional, default: "portrait"),
      #   page: {
      #     format: String (optional, use either format or width/height),
      #     width: Float >= 0.0352 (optional, default: 21.59),
      #     height: Float >= 0.0352 (optional, default: 27.94)
      #   },
      #   pageRanges: Array of Integers or Strings (optional),
      #   scale: Float between 0.1 and 2.0 (optional, default: 1.0),
      #   shrinkToFit: Boolean (optional, default: true)
      # }
      #
      # This validator checks presence, types, allowed ranges, and values,
      # and raises ArgumentError with a descriptive message if validation fails.
      class PrintParametersValidator
        def self.validate!(params)
          new(params).validate!
        end

        def initialize(params)
          @params = params
        end

        def validate!
          raise ArgumentError, "params must be a Hash" unless @params.is_a?(Hash)

          validate_boolean(:background)
          validate_boolean(:shrinkToFit)
          validate_orientation
          validate_scale
          validate_page_ranges
          validate_margin
          validate_page_size

          true
        end

        private

        def validate_boolean(key)
          return unless @params.key?(key)
          return if [true, false].include?(@params[key])

          raise ArgumentError, ":#{key} must be a boolean"
        end

        def validate_orientation
          return unless @params.key?(:orientation)
          return if %w[portrait landscape].include?(@params[:orientation])

          raise ArgumentError, ":orientation must be 'portrait' or 'landscape'"
        end

        def validate_scale
          return unless @params.key?(:scale)

          scale = @params[:scale]
          return if scale.is_a?(Numeric) && scale >= 0.1 && scale <= 2.0

          raise ArgumentError, ":scale must be a number between 0.1 and 2.0"
        end

        def validate_page_ranges
          return unless @params.key?(:pageRanges)
          unless @params[:pageRanges].is_a?(Array) &&
            @params[:pageRanges].all? { |v| v.is_a?(Integer) || v.is_a?(String) }
            raise ArgumentError, ":pageRanges must be an array of integers or strings"
          end
        end

        def validate_margin
          return unless @params.key?(:margin)

          margin = @params[:margin]
          raise ArgumentError, ":margin must be a Hash" unless margin.is_a?(Hash)

          %i[top bottom left right].each do |side|
            next unless margin.key?(side)

            val = margin[side]
            raise ArgumentError, "margin[:#{side}] must be a float >= 0.0" unless val.is_a?(Numeric) && val >= 0.0
          end
        end

        # rubocop: disable Metrics/CyclomaticComplexity
        def validate_page_size
          return unless @params.key?(:page)

          page = @params[:page]
          raise ArgumentError, ":page must be a Hash" unless page.is_a?(Hash)

          Bidi2pdf.translate_paper_format @params[:page][:format] if @params[:page][:format]

          %i[width height].each do |dim|
            next unless page.key?(dim)

            val = page[dim]
            raise ArgumentError, "page[:#{dim}] must be a float >= 0.0352" unless val.is_a?(Numeric) && val >= 0.0352
          end
          # rubocop: enable Metrics/CyclomaticComplexity
        end
      end
    end
  end
end
