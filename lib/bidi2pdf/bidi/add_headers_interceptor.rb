# frozen_string_literal: true

require_relative "interceptor"

module Bidi2pdf
  module Bidi
    class AddHeadersInterceptor
      include Interceptor

      class << self
        def phases = [Bidi2pdf::Bidi::Commands::AddIntercept::BEFORE_REQUEST]

        def events = ["network.beforeRequestSent"]
      end

      attr_reader :headers, :url_patterns, :context

      def initialize(headers:, url_patterns:, context:)
        @headers = headers.map do |header|
          {
            name: header[:name],
            value: {
              type: "string",
              value: header[:value]
            }
          }
        end

        @url_patterns = url_patterns
        @context = context
      end

      def process_interception(_event_response, _navigation_id, network_id, _url)
        client.send_cmd "network.continueRequest", {
          request: network_id,
          headers: headers
        }
      end
    end
  end
end
