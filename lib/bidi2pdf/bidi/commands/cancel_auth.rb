# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module Commands
      class CancelAuth
        include Base

        def initialize(request:)
          @request = request
        end

        def params
          {
            request: @request,
            action: "cancel"
          }
        end

        def method_name
          "network.continueWithAuth"
        end
      end
    end
  end
end
