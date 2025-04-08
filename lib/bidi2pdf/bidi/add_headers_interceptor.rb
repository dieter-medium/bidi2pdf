# frozen_string_literal: true

require_relative "interceptor"

module Bidi2pdf
  module Bidi
    class AddHeadersInterceptor
      include Interceptor

      class << self
        def phases = [Interceptor::Phases::BEFORE_REQUEST]

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

      def handle_event(response)
        event_response = response["params"]

        return unless event_response["intercepts"]&.include?(interceptor_id) && event_response["isBlocked"]

        network_id = event_response["request"]["request"]

        Bidi2pdf.logger.debug "Interceptor #{interceptor_id} handle event: #{network_id}"

        client.send_cmd "network.continueRequest", {
          request: network_id,
          headers: headers
        }
      end
    end
  end
end
