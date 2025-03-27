# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    class AuthInterceptor
      attr_reader :id, :username, :password, :network_ids

      def initialize(id, username, password, client)
        @id = id
        @client = client
        @username = username
        @password = password
        @network_ids = []
      end

      # rubocop:disable Metrics/AbcSize
      def handle_event(response)
        event_response = response["params"]

        return unless event_response["intercepts"]&.include?(id) && event_response["isBlocked"]

        navigation_id = event_response["navigation"]
        network_id = event_response["request"]["request"]
        url = event_response["request"]["url"]

        handle_bad_credentials(navigation_id, network_id, url)

        network_ids << network_id

        Bidi2pdf.logger.debug "Auth-Interceptor #{id} handle event: #{navigation_id}/#{network_id}/#{url}"

        client.send_cmd("network.continueWithAuth", {
          request: network_id,
          action: "provideCredentials",
          credentials: {
            type: "password",
            username: username,
            password: password
          }
        })
      end

      # rubocop:enable Metrics/AbcSize

      private

      def handle_bad_credentials(navigation_id, network_id, url)
        return unless network_ids.include?(network_id)

        network_ids.delete(network_id)

        Bidi2pdf.logger.debug "Auth-Interceptor #{id} already handled event: #{navigation_id}/#{network_id}/#{url}"

        # rubocop: disable Layout/LineLength
        Bidi2pdf.logger.error "It seems that the same request is being intercepted multiple times. Check your credentials or the URL you are trying to access. If you are using a proxy, make sure it is configured correctly."
        # rubocop: enable Layout/LineLength

        client.send_cmd("network.continueWithAuth", {
          request: network_id,
          action: "cancel"
        })
      end

      attr_reader :client
    end
  end
end
