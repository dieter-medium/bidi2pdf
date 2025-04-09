# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module Commands
      class BrowsingContextClose
        include Base

        def initialize(context:)
          @context = context
        end

        def params
          {
            context: @context
          }
        end

        def method_name
          "browsingContext.close"
        end
      end
    end
  end
end
