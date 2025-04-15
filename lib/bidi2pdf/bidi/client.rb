# frozen_string_literal: true

require "json"
require "websocket-client-simple"

require_relative "web_socket_dispatcher"
require_relative "command_manager"
require_relative "connection_manager"
require_relative "commands"

module Bidi2pdf
  module Bidi
    # Represents a WebSocket client for managing communication with a remote server
    # using the Bidi2pdf library. This class handles the setup, connection, and
    # communication with the WebSocket server, including sending commands and
    # handling responses.
    #
    # @example Creating and starting a client
    #   client = Bidi2pdf::Bidi::Client.new("ws://example.com/socket")
    #   client.start
    #
    # @example Sending a command
    #   command = Bidi2pdf::Bidi::Commands::ScriptEvaluate.new context: browsing_context_id, expression: script
    #   client.send_cmd(command)
    #
    # @example Subscribing to events
    #   client.on_event("eventName") do |event_data|
    #     puts "Received event: #{event_data}"
    #   end
    #
    # @param [String] ws_url The WebSocket URL to connect to.
    class Client
      # @return [String] The WebSocket URL.
      attr_reader :ws_url

      # Initializes a new WebSocket client.
      #
      # @param [String] ws_url The WebSocket URL to connect to.
      def initialize(ws_url)
        @ws_url = ws_url
        @started = false
        @connection_manager = ConnectionManager.new(logger: Bidi2pdf.logger)
      end

      # Starts the WebSocket client and establishes a connection.
      #
      # @return [WebSocket::Client::Simple] The WebSocket connection object.
      def start
        return @socket if started?

        WebSocket::Client::Simple.connect(ws_url) do |socket|
          @socket = socket
          @command_manager = CommandManager.new(@socket)

          dispatcher.on_open { @connection_manager.mark_connected }
          dispatcher.on_message { |data| handle_response_to_cmd(data) }
          dispatcher.start_listening
        end

        @started = true

        @socket
      end

      # Checks if the WebSocket client has started.
      #
      # @return [Boolean] True if the client has started, false otherwise.
      def started? = @started

      # Waits until the WebSocket connection is open.
      #
      # @param [Integer] timeout The timeout duration in seconds.
      # @raise [Bidi2pdf::WebsocketError] If the connection is not established within the timeout.
      def wait_until_open(timeout: Bidi2pdf.default_timeout)
        @connection_manager.wait_until_open(timeout: timeout)
      rescue Bidi2pdf::WebsocketError => e
        raise Bidi2pdf::WebsocketError, "Client#start must be called within #{timeout} sec." unless started?

        raise e
      end

      # Sends a command to the WebSocket server.
      #
      # @param [Bidi2pdf::Bidi::Commands::Base] cmd The command to send.
      # @raise [Bidi2pdf::ClientError] If the client has not started.
      def send_cmd(cmd)
        raise Bidi2pdf::ClientError, "Client#start must be called before" unless started?

        @command_manager.send_cmd(cmd)
      end

      # Sends a command to the WebSocket server and waits for a response.
      #
      # @param [Object] cmd The command to send.
      # @param [Integer] timeout The timeout duration in seconds.
      # @yield [response] A block to handle the response.
      # @raise [Bidi2pdf::ClientError] If the client has not started.
      def send_cmd_and_wait(cmd, timeout: Bidi2pdf.default_timeout, &)
        raise Bidi2pdf::ClientError, "Client#start must be called before" unless started?

        @command_manager.send_cmd_and_wait(cmd, timeout: timeout, &)
      end

      # Registers a callback for incoming WebSocket messages.
      #
      # @yield [message] A block to handle the incoming message.
      def on_message(&) = dispatcher.on_message(&)

      # Registers a callback for when the WebSocket connection is opened.
      #
      # @yield A block to execute when the connection is opened.
      def on_open(&) = dispatcher.on_open(&)

      # Registers a callback for when the WebSocket connection is closed.
      #
      # @yield A block to execute when the connection is closed.
      def on_close(&) = dispatcher.on_close(&)

      # Registers a callback for WebSocket errors.
      #
      # @yield [error] A block to handle the error.
      def on_error(&) = dispatcher.on_error(&)

      # Subscribes to specific WebSocket events.
      #
      # @param [Array<String>] names The names of the events to subscribe to.
      # @yield [event_data] A block to handle the event data.
      def on_event(*names, &block)
        names.each { |name| dispatcher.on_event(name, &block) }
        cmd = Bidi2pdf::Bidi::Commands::SessionSubscribe.new(events: names)
        send_cmd(cmd) if names.any?
      end

      # Removes a message listener.
      #
      # @param [Proc] block The listener block to remove.
      def remove_message_listener(block) = dispatcher.remove_message_listener(block)

      # Removes event listeners for specific events.
      #
      # @param [Array<String>] names The names of the events to unsubscribe from.
      # @param [Proc] block The listener block to remove.
      def remove_event_listener(*names, &block)
        names.each { |event_name| dispatcher.remove_event_listener(event_name, block) }
      end

      # Closes the WebSocket connection.
      def close
        return unless @socket

        Bidi2pdf.logger.debug "Closing WebSocket connection"
        @socket&.close
        @socket = nil
        @started = false
      end

      private

      # Returns the WebSocket dispatcher for managing events and messages.
      #
      # @return [WebSocketDispatcher] The dispatcher instance.
      def dispatcher
        @dispatcher ||= WebSocketDispatcher.new(@socket)
      end

      # Handles responses to commands sent to the WebSocket server.
      #
      # @param [Hash] data The response data.
      def handle_response_to_cmd(data)
        @command_manager.handle_response(data)
      end
    end
  end
end
