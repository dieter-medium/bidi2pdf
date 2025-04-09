# frozen_string_literal: true

require_relative "interceptor"

module Bidi2pdf
  module Bidi
    class AuthInterceptor
      include Interceptor

      class << self
        def phases = [Bidi2pdf::Bidi::Commands::AddIntercept::AUTH_REQUIRED]

        def events = ["network.authRequired"]
      end

      attr_reader :headers, :url_patterns, :context, :username, :password, :network_ids

      def initialize(username:, password:, url_patterns:, context:)
        @url_patterns = url_patterns
        @context = context
        @username = username
        @password = password
        @network_ids = []
      end

      def process_interception(_event_response, navigation_id, network_id, url)
        handle_bad_credentials(navigation_id, network_id, url)

        network_ids << network_id

        cmd = Bidi2pdf::Bidi::Commands::ProvideCredentials.new request: network_id, username: username, password: password

        client.send_cmd(cmd)
      rescue StandardError => e
        Bidi2pdf.logger.error "Error handling auth event: #{e.message}"
        Bidi2pdf.logger.error e.backtrace.join("\n")
        raise e
      end

      private

      def handle_bad_credentials(navigation_id, network_id, url)
        return unless network_ids.include?(network_id)

        network_ids.delete(network_id)

        Bidi2pdf.logger.debug "Auth-Interceptor #{interceptor_id} already handled event: #{navigation_id}/#{network_id}/#{url}"

        Bidi2pdf.logger.error "It seems that the same request is being intercepted multiple times. Check your credentials or the URL you are trying to access. If you are using a proxy, make sure it is configured correctly."
        # rubocop: enable Layout/LineLength

        cmd = Bidi2pdf::Bidi::Commands::CancelAuth.new request: network_id

        client.send_cmd(cmd)
      end
    end
  end
end
