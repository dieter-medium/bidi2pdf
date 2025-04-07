# frozen_string_literal: true

require_relative "network_event"

module Bidi2pdf
  module Bidi
    class NetworkEvents
      attr_reader :context_id, :events

      def initialize(context_id)
        @context_id = context_id
        @events = {}
      end

      def handle_event(data)
        event = data["params"]
        method = data["method"]

        if event["context"] == context_id
          handle_response(method, event)
        else
          Bidi2pdf.logger.debug "Ignoring Network event: #{method}, #{context_id}, params: #{event}"
        end
      rescue StandardError => e
        Bidi2pdf.logger.error "Error handling network event: #{e.message}"
      end

      # rubocop:disable Metrics/AbcSize
      def handle_response(method, event)
        return unless event && event["request"]

        request = event["request"]

        id = request["request"]
        url = request["url"]
        timing = request["timings"]

        timestamp = event["timestamp"]

        if method == "network.responseStarted"
          events[id] ||= NetworkEvent.new(
            id: id,
            url: url,
            timestamp: timestamp,
            timing: timing,
            state: method
          )
        elsif events.key?(id)
          events[id].update_state(method, timestamp: timestamp, timing: timing)
        else
          Bidi2pdf.logger.warn "Received response for unknown request ID: #{id}, URL: #{url}"
        end
      end

      # rubocop:enable Metrics/AbcSize

      def all_events
        events.values.sort_by(&:start_timestamp)
      end

      def wait_until_all_finished(timeout: 10, poll_interval: 0.1)
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
