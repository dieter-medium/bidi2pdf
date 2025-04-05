# frozen_string_literal: true

require "json"
require "websocket-client-simple"

require_relative "web_socket_dispatcher"
require_relative "add_headers_interceptor"
require_relative "auth_interceptor"
require_relative "command_manager"
require_relative "connection_manager"

module Bidi2pdf
  module Bidi
    class Client
      include Bidi2pdf::Utils

      attr_reader :ws_url

      def initialize(ws_url)
        @ws_url = ws_url
        @started = false
      end

      def start
        return @socket if started?

        @socket = WebSocket::Client::Simple.connect(ws_url)

        @connection_manager = ConnectionManager.new(logger: Bidi2pdf.logger)
        @command_manager = CommandManager.new(@socket, logger: Bidi2pdf.logger)

        dispatcher.on_open { @connection_manager.mark_connected }
        dispatcher.on_message { |data| handle_response_to_cmd(data) }

        dispatcher.start_listening
        @started = true

        @socket
      end

      def started? = @started

      def wait_until_open(timeout: Bidi2pdf.default_timeout)
        @connection_manager.wait_until_open(timeout: timeout)
      end

      def send_cmd(method, params = {})
        @command_manager.send_cmd(method, params)
      end

      def send_cmd_and_wait(method, params = {}, timeout: Bidi2pdf.default_timeout, &block)
        timed("Command #{method}") do
          @command_manager.send_cmd_and_wait(method, params, timeout: timeout, &block)
        end
      end

      def on_message(&block) = dispatcher.on_message(&block)

      def on_open(&block) = dispatcher.on_open(&block)

      def on_close(&block) = dispatcher.on_close(&block)

      def on_error(&block) = dispatcher.on_error(&block)

      def on_event(*names, &block)
        names.each { |name| dispatcher.on_event(name, &block) }
        send_cmd("session.subscribe", { events: names }) if names.any?
      end

      def remove_message_listener(block) = dispatcher.remove_message_listener(block)

      def remove_event_listener(*names, &block)
        names.each { |event_name| dispatcher.remove_event_listener(event_name, block) }
      end

      def add_headers_interceptor(context:, url_patterns:, headers:)
        add_interceptor(
          context: context,
          url_patterns: url_patterns,
          phase: "beforeRequestSent",
          event: "network.beforeRequestSent",
          interceptor_class: AddHeadersInterceptor,
          extra_args: { headers: headers }
        )
      end

      def add_auth_interceptor(context:, url_patterns:, username:, password:)
        add_interceptor(
          context: context,
          url_patterns: url_patterns,
          phase: "authRequired",
          event: "network.authRequired",
          interceptor_class: AuthInterceptor,
          extra_args: { username: username, password: password }
        )
      end

      private

      def dispatcher
        @dispatcher ||= WebSocketDispatcher.new(@socket)
      end

      def handle_response_to_cmd(data)
        handled = @command_manager.handle_response(data)
        return if handled

        if data["error"]
          Bidi2pdf.logger.error "Error response: #{data["error"].inspect}"
        else
          Bidi2pdf.logger.warn "Unknown response: #{data.inspect}"
        end
      end

      def add_interceptor(context:, url_patterns:, phase:, event:, interceptor_class:, extra_args: {})
        send_cmd_and_wait("network.addIntercept", {
          context: context,
          phases: [phase],
          urlPatterns: url_patterns
        }) do |response|
          id = response["result"]["intercept"]
          Bidi2pdf.logger.debug "Interceptor added: #{id}"

          interceptor_class.new(id, **extra_args, client: self).tap do |interceptor|
            on_event(event, &interceptor.method(:handle_event))
          end
        end
      end
    end
  end
end
