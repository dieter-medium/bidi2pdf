# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    class ConnectionManager
      def initialize(logger:)
        @logger = logger
        @connected = false
        @connection_queue = Thread::Queue.new
      end

      def mark_connected
        return if @connected

        @connected = true
        @logger.debug "WebSocket connection is open"
        @connection_queue.push(true)
      end

      def wait_until_open(timeout:)
        return true if @connected

        @logger.debug "Waiting for WebSocket connection to open"

        begin
          Timeout.timeout(timeout) do
            @connection_queue.pop
          end
        rescue Timeout::Error
          raise Bidi2pdf::WebsocketError, "WebSocket connection did not open in time #{timeout} sec."
        end

        true
      end
    end
  end
end
