# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module Interceptor
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def phases = raise(NotImplementedError, "Interceptors must implement phases")

        def events = raise(NotImplementedError, "Interceptors must implement events")
      end

      def url_patterns = raise(NotImplementedError, "Interceptors must implement url_patterns")

      def context = raise(NotImplementedError, "Interceptors must implement context")

      def process_interception(_event_response, _navigation_id, _network_id, _url) = raise(NotImplementedError, "Interceptors must implement process_interception")

      def register_with_client(client:)
        @client = client

        cmd = Bidi2pdf::Bidi::Commands::AddIntercept.new context: context, phases: self.class.phases, url_patterns: url_patterns

        client.send_cmd_and_wait(cmd) do |response|
          @interceptor_id = response["result"]["intercept"]

          Bidi2pdf.logger.debug "Interceptor added: #{@interceptor_id}"

          client.on_event(*self.class.events, &method(:handle_event))

          self
        end
      end

      # rubocop: disable Metrics/AbcSize
      def handle_event(response)
        event_response = response["params"]

        return unless event_response["intercepts"]&.include?(interceptor_id) && event_response["isBlocked"]

        navigation_id = event_response["navigation"]
        network_id = event_response["request"]["request"]
        url = event_response["request"]["url"]

        # Log the interception
        Bidi2pdf.logger.debug1 "Interceptor #{interceptor_id} handling event: #{navigation_id}/#{network_id}/#{url}"

        process_interception(event_response, navigation_id, network_id, url)
      rescue StandardError => e
        Bidi2pdf.logger.error "Error handling event: #{e.message}"
        Bidi2pdf.logger.error e.backtrace.join("\n")
        raise e
      end

      # rubocop: enable Metrics/AbcSize

      def interceptor_id
        @interceptor_id
      end

      def client
        @client
      end

      def validate_phases!
        valid_phases = [Phases::BEFORE_REQUEST, Phases::RESPONSE_STARTED, Phases::AUTH_REQUIRED]

        raise ArgumentError, "Unsupported phase(s): #{self.class.phases}" unless self.class.phases.all? { |phase| valid_phases.include?(phase) }
      end
    end
  end
end
