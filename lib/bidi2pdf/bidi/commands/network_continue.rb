# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module Commands
      class NetworkContinue
        include Base

        attr_reader :request, :headers

        def initialize(request:, headers:)
          @headers = headers
          @request = request
        end

        def method_name
          "network.continueRequest"
        end

        def params
          {
            request: request,
            headers: headers
          }.compact
        end
      end
    end
  end
end
