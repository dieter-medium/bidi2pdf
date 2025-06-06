# frozen_string_literal: true

require_relative "event_manager"

module Bidi2pdf
  module Bidi
    class WebSocketDispatcher
      attr_reader :socket_events, :session_events

      def initialize(socket)
        @socket = socket
        @socket_events = EventManager.new("socket-event")
        @session_events = EventManager.new("session-event")
      end

      def start_listening
        Bidi2pdf.logger.debug "Registering WebSocket event listeners"

        setup_connection_lifecycle_handlers
        setup_message_handler
      end

      # Add listeners

      def on_message(&) = socket_events.on(:message, &)

      def on_event(*event_names, &) = session_events.on(*event_names, &)

      def on_open(&) = socket_events.on(:open, &)

      def on_close(&) = socket_events.on(:close, &)

      def on_error(&) = socket_events.on(:error, &)

      def remove_message_listener(block) = socket_events.off(:message, block)

      def remove_event_listener(name, listener) = session_events.off(name, listener)

      def remove_open_listener(listener) = socket_events.off(:open, listener)

      def remove_close_listener(listener) = socket_events.off(:close, listener)

      def remove_error_listener(listener) = socket_events.off(:error, listener)

      private

      def setup_message_handler
        that = self

        @socket.on(:message) do |msg|
          data = JSON.parse(msg.data)
          method = data["method"]

          if method
            Bidi2pdf.logger.debug3 "Dispatching session event: #{method}"
            that.session_events.dispatch(method, data)
          else
            Bidi2pdf.logger.debug3 "Dispatching socket message"
            that.socket_events.dispatch(:message, data)
          end
        end
      end

      def setup_connection_lifecycle_handlers
        that = self
        @socket.on(:open) { |e| that.socket_events.dispatch(:open, e) }
        @socket.on(:close) { |e| that.socket_events.dispatch(:close, e) }
        @socket.on(:error) { |e| that.socket_events.dispatch(:error, e) }
      end
    end
  end
end
