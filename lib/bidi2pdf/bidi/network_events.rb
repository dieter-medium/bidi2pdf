# frozen_string_literal: true

require_relative "network_event"
require_relative "network_event_formatters"

module Bidi2pdf
  module Bidi
    class NetworkEvents
      attr_reader :context_id, :events, :network_event_formatter

      def initialize(context_id)
        @context_id = context_id
        @events = {}
        @network_event_formatter = NetworkEventFormatters::NetworkEventConsoleFormatter.new
      end

      def handle_event(data)
        event = data["params"]
        method = data["method"]

        if event["context"] == context_id
          handle_response(method, event)
        else
          Bidi2pdf.logger.debug3 "Ignoring Network event: #{method}, #{context_id}, params: #{event}"
        end
      rescue StandardError => e
        Bidi2pdf.logger.error "Error handling network event: #{e.message}"
      end

      # rubocop:disable Metrics/AbcSize
      def handle_response(method, event)
        return unless event && event["request"]

        request = event["request"]
        response = event["response"]
        http_status_code = response&.dig("status")
        bytes_received = response&.dig("bytesReceived")

        id = request["request"]
        url = request["url"]
        timing = request["timings"]
        http_method = request["method"]

        timestamp = event["timestamp"]

        if method == "network.beforeRequestSent"
          events[id] ||= NetworkEvent.new(
            id: id,
            url: url,
            timestamp: timestamp,
            timing: timing,
            state: method,
            http_method: http_method
          )
        elsif events.key?(id)
          events[id].update_state(method, timestamp: timestamp, timing: timing, http_status_code: http_status_code, bytes_received: bytes_received)
        else
          Bidi2pdf.logger.warn "Received response for unknown request ID: #{id}, URL: #{url}"
        end
      end

      # rubocop:enable Metrics/AbcSize

      def all_events
        events.values.sort_by(&:start_timestamp)
      end

      def log_network_traffic(format: :console)
        format = format.to_sym

        if format == :console
          NetworkEventFormatters::NetworkEventConsoleFormatter.new.log all_events
        elsif format == :html
          NetworkEventFormatters::NetworkEventHtmlFormatter.new.render(all_events)
        else
          raise ArgumentError, "Unknown network event format: #{format}"
        end
      end

      def wait_until_network_idle(timeout: 10, poll_interval: 0.01)
        start_time = Time.now

        loop do
          unless events.values.any?(&:in_progress?)
            Bidi2pdf.logger.debug "✅ All network events completed."
            break
          end

          if Time.now - start_time > timeout
            Bidi2pdf.logger.warn "⏰ Timeout while waiting for network events to complete. Still in progress: #{in_progress.map(&:id)}"
            # rubocop:enable Layout/LineLength
            break
          end

          sleep(poll_interval)
        end
      end
    end
  end
end
