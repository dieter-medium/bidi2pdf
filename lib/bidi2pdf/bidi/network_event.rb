# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    class NetworkEvent
      attr_reader :id, :url, :state, :start_timestamp, :end_timestamp, :timing, :http_status_code,
                  :http_method, :bytes_received

      STATE_MAP = {
        "network.responseStarted" => "started",
        "network.responseCompleted" => "completed",
        "network.fetchError" => "error"
      }.freeze

      def initialize(id:, url:, timestamp:, timing:, state:, http_status_code: nil, http_method: nil)
        @id = id
        @url = url
        @start_timestamp = timestamp
        @timing = timing
        @state = map_state(state)
        @http_status_code = http_status_code
        @http_method = http_method
      end

      def update_state(new_state, timestamp: nil, timing: nil, http_status_code: nil, bytes_received: nil)
        @state = map_state(new_state)
        @end_timestamp = timestamp if timestamp
        @timing = timing if timing
        @http_status_code = http_status_code if http_status_code
        @bytes_received = bytes_received if bytes_received
      end

      def map_state(state)
        STATE_MAP.fetch(state, state)
      end

      def format_timestamp(timestamp)
        return "N/A" unless timestamp

        Time.at(timestamp / 1000.0).utc.strftime("%Y-%m-%d %H:%M:%S.%L UTC")
      end

      def duration_seconds
        return nil unless @start_timestamp && @end_timestamp

        ((@end_timestamp - @start_timestamp) / 1000.0).round(3)
      end

      def in_progress? = state == "started"

      def to_s
        took_str = duration_seconds ? "#{duration_seconds.round(2)} sec" : "in progress"
        http_status = @http_status_code ? "HTTP #{@http_status_code}" : "HTTP (N/A)"
        start_str = format_timestamp(@start_timestamp) || "N/A"
        end_str = format_timestamp(@end_timestamp) || "N/A"
        method_str = @http_method || "N/A"
        bytes_str = @bytes_received ? "#{@bytes_received} bytes" : "0 bytes"

        "#<NetworkEvent " \
          "id=#{@id.inspect}, " \
          "method=#{method_str.inspect}, " \
          "url=#{@url.inspect}, " \
          "state=#{@state.inspect}, " \
          "#{http_status}, " \
          "bytes_received=#{bytes_str}, " \
          "start=#{start_str}, " \
          "end=#{end_str}, " \
          "duration=#{took_str}>"
      end

      def dup
        self.class.new(
          id: @id,
          url: @url,
          timestamp: @start_timestamp,
          timing: @timing&.dup,
          state: @state,
          http_status_code: @http_status_code,
          http_method: @http_method
        ).tap do |duped|
          duped.instance_variable_set(:@end_timestamp, @end_timestamp)
          duped.instance_variable_set(:@bytes_received, @bytes_received)
        end
      end
    end
  end
end
