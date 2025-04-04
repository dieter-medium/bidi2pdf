# frozen_string_literal: true

require "json"
require "websocket-client-simple"

require_relative "web_socket_dispatcher"
require_relative "add_headers_interceptor"
require_relative "auth_interceptor"

module Bidi2pdf
  module Bidi
    class Client
      include Bidi2pdf::Utils

      attr_reader :ws_url

      def initialize(ws_url)
        @ws_url = ws_url
        @id = 0
        @pending_responses = {}

        @connected = false
        @connection_mutex = Mutex.new
        @send_cmd_mutex = Mutex.new
        @connection_cv = ConditionVariable.new

        @started = false
      end

      def start
        return @socket if started?

        @socket = WebSocket::Client::Simple.connect(ws_url)
        @dispatcher = WebSocketDispatcher.new(@socket)

        @dispatcher.on_open { handle_open }
        @dispatcher.on_message { |data| handle_response_to_cmd(data) }

        @dispatcher.start_listening

        @started = true

        @socket
      end

      def started?
        @started
      end

      def wait_until_open(timeout: Bidi2pdf.default_timeout)
        @connection_mutex.synchronize do
          unless @connected
            Bidi2pdf.logger.debug "Waiting for WebSocket connection to open"
            @connection_cv.wait(@connection_mutex, timeout)
          end
        end

        raise "WebSocket connection did not open in time" unless @connected

        Bidi2pdf.logger.debug "WebSocket connection is open"
      end

      def send_cmd(method, params = {})
        next_id.tap do |cmd_id|
          payload = {
            id: cmd_id,
            method: method,
            params: params
          }

          Bidi2pdf.logger.debug "Sending command: #{redact_sensitive_fields(payload).inspect}"

          @socket.send(payload.to_json)
        end
      end

      # rubocop:disable Metrics/AbcSize
      def send_cmd_and_wait(method, params = {}, timeout: Bidi2pdf.default_timeout)
        timed("Command #{method}") do
          id = send_cmd(method, params)
          queue = @pending_responses[id]

          response = queue.pop(timeout: timeout)

          if response.nil?
            # rubocop:disable Layout/LineLength
            Bidi2pdf.logger.error "Timeout waiting for response to command #{id}, cmd: #{method}, params: #{redact_sensitive_fields(params).inspect}"
            # rubocop:enable Layout/LineLength

            raise "Timeout waiting for response to command ID #{id}"
          end

          raise "Error response: #{response["error"]}" if response["error"]

          result = response

          result = yield response if block_given?

          result
        ensure
          @pending_responses.delete(id)
        end
      end

      # rubocop:enable Metrics/AbcSize

      # Event API for external consumers
      def on_message(&block) = @dispatcher.on_message(&block)

      def on_open(&block) = @dispatcher.on_open(&block)

      def on_close(&block) = @dispatcher.on_close(&block)

      def on_error(&block) = @dispatcher.on_error(&block)

      def on_event(*names, &block)
        names.each do |name|
          @dispatcher.on_event(name, &block)
        end

        send_cmd "session.subscribe", { events: names } if names.any?
      end

      def remove_message_listener(block) = @dispatcher.remove_message_listener(block)

      def remove_event_listener(*names, &block)
        names.each do |event_name|
          @dispatcher.remove_event_listener(event_name, block)
        end
      end

      def add_headers_interceptor(
        context:,
        url_patterns:,
        headers:
      )
        send_cmd_and_wait("network.addIntercept", {
          context: context,
          phases: ["beforeRequestSent"],
          urlPatterns: url_patterns
        }) do |response|
          id = response["result"]["intercept"]
          Bidi2pdf.logger.debug "Interceptor added: #{id}"

          AddHeadersInterceptor.new(id, headers, self).tap do |interceptor|
            on_event "network.beforeRequestSent", &interceptor.method(:handle_event)
          end
        end
      end

      def add_auth_interceptor(
        context:,
        url_patterns:,
        username:,
        password:
      )
        send_cmd_and_wait("network.addIntercept", {
          context: context,
          phases: ["authRequired"],
          urlPatterns: url_patterns
        }) do |response|
          id = response["result"]["intercept"]
          Bidi2pdf.logger.debug "Interceptor added: #{id}"

          AuthInterceptor.new(id, username, password, self).tap do |interceptor|
            on_event "network.authRequired", &interceptor.method(:handle_event)
          end
        end
      end

      private

      def next_id
        cmd_id = nil

        @send_cmd_mutex.synchronize do
          @id += 1
          cmd_id = @id
          @pending_responses[cmd_id] = Thread::Queue.new
        end

        cmd_id
      end

      def handle_open
        @connection_mutex.synchronize do
          @connected = true
          @connection_cv.broadcast
        end
      end

      def handle_response_to_cmd(data)
        if (id = data["id"]) && @pending_responses.key?(id)
          @pending_responses[id]&.push(data)
        elsif (data = data["error"])
          Bidi2pdf.logger.error "Error response: #{data.inspect}"
        else
          Bidi2pdf.logger.warn "Unknown response: #{data.inspect}"
        end
      end

      def redact_sensitive_fields(obj, sensitive_keys = %w[value token password authorization username])
        case obj
        when Hash
          obj.each_with_object({}) do |(k, v), result|
            result[k] = if sensitive_keys.include?(k.to_s.downcase)
                          "[REDACTED]"
                        else
                          redact_sensitive_fields(v, sensitive_keys)
                        end
          end
        when Array
          obj.map { |item| redact_sensitive_fields(item, sensitive_keys) }
        else
          obj
        end
      end
    end
  end
end
