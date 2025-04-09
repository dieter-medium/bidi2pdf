# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module Commands
      class BrowsingContextNavigate
        include Base

        def initialize(url:,
                       context:,
                       wait: "complete")
          @url = url
          @context = context
          @wait = wait
        end

        def params
          {
            url: @url,
            context: @context,
            wait: @wait
          }
        end

        def method_name
          "browsingContext.navigate"
        end
      end
    end
  end
end
