# frozen_string_literal: true

module Bidi2pdf
  module Notifications
    # for reuse within ActiveSupport::LogSubscriber
    module LoggingSubscriberActions
      def handle_response(event)
        payload = event.payload

        if payload[:error]
          logger.error "Received error: #{payload[:error].inspect} for cmd: #{payload[:id] || "-"}"
        elsif !payload[:handled]
          Bidi2pdf.logger.warn "Unknown response: #{payload[:data].inspect}"
        end
      end

      def send_cmd(event)
        logger.debug "Sending command: #{event.payload[:cmd].method_name} id: ##{event.payload[:cmd_payload][:id]}"

        logger.debug1 do
          payload = redact_sensitive_fields(event.payload[:cmd_payload])
          "Sending command: #{payload.inspect} (#{event.duration.round(1)}ms)"
        end
      end

      def send_cmd_and_wait(event)
        return unless event.payload[:exception]

        payload = redact_sensitive_fields(event.payload[:cmd]&.params || {})
        logger.error "Error sending command: #{payload} (#{event.duration.round(1)}ms) - #{event.payload[:exception].inspect}"
      end

      def session_close(event)
        return unless event.payload[:error]

        logger.error "Session close error: #{event.payload[:error].inspect}, attempt: #{event.payload[:attempt]}, retry: #{event.payload[:retry]}"
      end

      # rubocop: disable Metrics/AbcSize
      def network_event_received(event)
        return unless logger.debug2?

        msg = case event.payload[:method]
              when "network.beforeRequestSent"
                "Request url '#{event.payload[:url]}' started"

              when "network.responseStarted"
                nil
              when "network.responseCompleted"
                "Request url '#{event.payload[:url]}' completed"
              when "network.fetchError"
                "Request url '#{event.payload[:url]}' error."
              else
                "Unknown network event: #{event.payload[:method]} for url '#{event.payload[:url]}'"
              end

        logger.debug2 msg if msg
      end

      # rubocop:disable  Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def network_idle(event)
        return unless logger.info?

        requests = event.payload[:requests]
        transfered = requests.map { |request| request.bytes_received || 0 }.sum
        status_counts = requests
                          .group_by { |evt| evt.http_status_code || 0 }
                          .transform_keys { |code| code.zero? || code.nil? ? "pending" : code.to_s }
                          .transform_values(&:count)
                          .map { |code, count| "#{code}: #{count}" }
                          .join(", ")

        logger.info "Network was idle after #{event.duration.round(1)}ms, #{requests.size} requests, " \
                      "transferred #{transfered} bytes (status codes: #{status_counts})"
      end

      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      def page_loaded(event)
        logger.info "Page loaded: #{event.duration.round(1)}ms"
      end

      def print(event)
        logger.info "Page printed: #{event.duration.round(1)}ms"
      end

      private

      def redact_sensitive_fields(obj, sensitive_keys = %w[value token password authorization username])
        case obj
        when Hash
          obj.transform_values.with_index do |v, idx|
            k = obj.keys[idx]
            sensitive_keys.include?(k.to_s.downcase) ? "[REDACTED]" : redact_sensitive_fields(v, sensitive_keys)
          end
        when Array
          obj.map { |item| redact_sensitive_fields(item, sensitive_keys) }
        else
          obj
        end
      end
    end

    class LoggingSubscriber
      include LoggingSubscriberActions

      attr_accessor :logger

      # rubocop: disable Metrics/AbcSize, Metrics/CyclomaticComplexity,  Metrics/PerceivedComplexity
      def initialize(logger: Logger.new($stdout))
        @logger = logger
        Bidi2pdf.notification_service&.subscribe("handle_response.bidi2pdf", &method(:handle_response))
        Bidi2pdf.notification_service&.subscribe("send_cmd.bidi2pdf", &method(:send_cmd))
        Bidi2pdf.notification_service&.subscribe("send_cmd_and_wait.bidi2pdf", &method(:send_cmd_and_wait))
        Bidi2pdf.notification_service&.subscribe("session_close.bidi2pdf", &method(:session_close))
        Bidi2pdf.notification_service&.subscribe("network_idle.bidi2pdf", &method(:network_idle))
        Bidi2pdf.notification_service&.subscribe("page_loaded.bidi2pdf", &method(:page_loaded))
        Bidi2pdf.notification_service&.subscribe("network_event_received.bidi2pdf", &method(:network_event_received))
        Bidi2pdf.notification_service&.subscribe("print.bidi2pdf", &method(:network_event_received))
      end

      def unsubscribe
        Bidi2pdf.notification_service&.unsubscribe("handle_response.bidi2pdf", &method(:handle_response))
        Bidi2pdf.notification_service&.unsubscribe("send_cmd.bidi2pdf", &method(:send_cmd))
        Bidi2pdf.notification_service&.unsubscribe("send_cmd_and_wait.bidi2pdf", &method(:send_cmd_and_wait))
        Bidi2pdf.notification_service&.unsubscribe("session_close.bidi2pdf", &method(:session_close))
        Bidi2pdf.notification_service&.unsubscribe("network_idle.bidi2pdf", &method(:network_idle))
        Bidi2pdf.notification_service&.unsubscribe("page_loaded.bidi2pdf", &method(:page_loaded))
        Bidi2pdf.notification_service&.unsubscribe("network_event_received.bidi2pdf", &method(:network_event_received))
        Bidi2pdf.notification_service&.unsubscribe("print.bidi2pdf", &method(:network_event_received))
      end

      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity,  Metrics/PerceivedComplexity
    end
  end
end
