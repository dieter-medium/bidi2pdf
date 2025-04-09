# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module Commands
      class ProvideCredentials
        include Base

        def initialize(request:, username:, password:)
          @request = request
          @username = username
          @password = password
        end

        def params
          {
            request: @request,
            action: "provideCredentials",
            credentials: {
              type: "password",
              username: @username,
              password: @password
            }
          }
        end

        def method_name
          "network.continueWithAuth"
        end
      end
    end
  end
end
