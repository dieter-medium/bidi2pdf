# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module Commands
      class CaptureScreenshot
        include Base

        attr_reader :context, :origin, :format, :clip

        def initialize(context:, origin: "document", format: nil, clip: nil)
          @context = context
          @origin = origin
          @format = format
          @clip = clip
        end

        def method_name
          "browsingContext.captureScreenshot"
        end

        def params
          {
            context: context,
            origin: origin,
            format: format,
            clip: clip
          }.compact
        end
      end
    end
  end
end
