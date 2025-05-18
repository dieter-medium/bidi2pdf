# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module Commands
      class CdpGetSession
        include Base

        def initialize(context:)
          @context = context
        end

        def params = { context: @context }

        def method_name
          "goog:cdp.getSession"
        end
      end
    end
  end
end
