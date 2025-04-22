# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    class ConnectionManager
      def initialize(logger:)
        @logger = logger
        @connected = false
        @connection_latch = Concurrent::CountDownLatch.new(1)
      end

      def mark_connected
        return if @connected

        @connected = true
        @logger.debug "WebSocket connection is open"
        @connection_latch.count_down
      end

      def wait_until_open(timeout:)
        return true if @connected

        @logger.debug "Waiting for WebSocket connection to open"

        raise Bidi2pdf::WebsocketError, "WebSocket connection did not open in time #{timeout} sec." unless @connection_latch.wait(timeout)

        true
      end
    end
  end
end
