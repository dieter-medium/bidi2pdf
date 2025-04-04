# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    class ConnectionManager
      def initialize(logger:)
        @logger = logger
        @connected = false
        @mutex = Mutex.new
        @cv = ConditionVariable.new
      end

      def mark_connected
        @mutex.synchronize do
          @connected = true
          @cv.broadcast
        end
      end

      def wait_until_open(timeout:)
        @mutex.synchronize do
          unless @connected
            @logger.debug "Waiting for WebSocket connection to open"
            @cv.wait(@mutex, timeout)
          end
        end

        raise "WebSocket connection did not open in time" unless @connected

        @logger.debug "WebSocket connection is open"
      end
    end
  end
end
