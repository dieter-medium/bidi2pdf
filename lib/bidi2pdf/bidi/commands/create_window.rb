# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module Commands
      class CreateWindow
        include Base

        def initialize(user_context_id: nil, reference_context: nil, background: false)
          @user_context_id = user_context_id
          @reference_context = reference_context
          @background = background
        end

        def method_name
          "browsingContext.create"
        end

        def params
          {
            type: type,
            userContext: @user_context_id,
            referenceContext: @reference_context,
            background: @background
          }.compact
        end

        def type = "window"
      end
    end
  end
end
