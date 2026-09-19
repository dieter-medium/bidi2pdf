# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module Commands
      class SetViewport
        include Base

        attr_reader :context, :width, :height, :device_pixel_ratio

        def initialize(context:, width:, height:, device_pixel_ratio: nil)
          @context = context
          @width = width
          @height = height
          @device_pixel_ratio = device_pixel_ratio
        end

        def method_name
          "browsingContext.setViewport"
        end

        def params
          {
            context: context,
            viewport: { width: width, height: height },
            devicePixelRatio: device_pixel_ratio
          }.compact
        end
      end
    end
  end
end
