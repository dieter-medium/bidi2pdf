# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    class AddHeadersInterceptor
      attr_reader :id, :headers

      def initialize(id, headers, client)
        @id = id
        @client = client
        @headers = headers.map do |header|
          {
            name: header[:name],
            value: {
              type: "string",
              value: header[:value]
            }
          }
        end
      end

      def handle_event(response)
        event_response = response["params"]

        return unless event_response["intercepts"]&.include?(id) && event_response["isBlocked"]

        network_id = event_response["request"]["request"]

        Bidi2pdf.logger.debug "Interceptor #{id} handle event: #{network_id}"

        client.send_cmd "network.continueRequest", {
          request: network_id,
          headers: headers
        }
      end

      private

      attr_reader :client
    end
  end
end
