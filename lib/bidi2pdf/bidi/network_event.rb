# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    class NetworkEvent
      attr_reader :id, :url, :state, :start_timestamp, :end_timestamp, :timing

      STATE_MAP = {
        "network.responseStarted" => "started",
        "network.responseCompleted" => "completed",
        "network.fetchError" => "error"
      }.freeze

      def initialize(id:, url:, timestamp:, timing:, state:)
        @id = id
        @url = url
        @start_timestamp = timestamp
        @timing = timing
        @state = map_state(state)
      end

      def update_state(new_state, timestamp: nil, timing: nil)
        @state = map_state(new_state)
        @end_timestamp = timestamp if timestamp
        @timing = timing if timing
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
        took_str = duration_seconds ? "took #{duration_seconds} sec" : "in progress"
        "#<NetworkEvent id=#{@id} url=#{@url} state=#{@state} " \
          "start=#{format_timestamp(@start_timestamp)} " \
          "end=#{format_timestamp(@end_timestamp)} #{took_str}>"
      end
    end
  end
end
