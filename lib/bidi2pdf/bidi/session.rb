# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require_relative "client"
require_relative "browser"
require_relative "user_context"

module Bidi2pdf
  module Bidi
    class Session
      SUBSCRIBE_EVENTS = %w[log script].freeze
      DEFAULT_CHROME_ARGS = %w[--disable-gpu --disable-popup-blocking --disable-hang-monitor].freeze

      attr_reader :session_uri, :started, :chrome_args

      def initialize(session_url:, headless: true, chrome_args: DEFAULT_CHROME_ARGS)
        @session_uri = URI(session_url)
        @headless = headless
        @started = false
        @chrome_args = chrome_args.dup
      end

      def start
        return if started?

        @started = true
        client
      rescue StandardError => e
        @started = false
        raise e
      end

      def client
        @client ||= started? ? create_client : nil
      end

      def browser
        @browser ||= create_browser
      end

      def close
        return unless started?

        2.times do |attempt|
          client&.send_cmd_and_wait(Bidi2pdf::Bidi::Commands::SessionEnd.new, timeout: 1) do |response|
            Bidi2pdf.logger.info "Session ended: #{response}"

            cleanup
          end
          break
        rescue CmdTimeoutError
          Bidi2pdf.logger.error "Session end command timed out. Retrying... (#{attempt + 1})"
        end
      end

      def user_contexts
        send_cmd(Bidi2pdf::Bidi::Commands::GetUserContexts.new) { |resp| Bidi2pdf.logger.debug "User contexts: #{resp}" }
      end

      def status
        send_cmd(Bidi2pdf::Bidi::Commands::SessionStatus.new) { |resp| Bidi2pdf.logger.info "Session status: #{resp.inspect}" }
      end

      def started?
        @started
      end

      def websocket_url
        return @websocket_url if @websocket_url

        @websocket_url = if %w[ws wss].include?(session_uri.scheme)
                           session_uri.to_s
                         else
                           create_new_session
                         end
      end

      private

      def send_cmd(command, &block)
        client&.send_cmd_and_wait(command, &block)
      end

      # rubocop: disable Metrics/AbcSize
      def create_browser
        start
        client.start
        client.wait_until_open

        Bidi2pdf.logger.info "Subscribing to events"

        Bidi::Client.new(websocket_url).tap do |event_client|
          event_client.start
          event_client.wait_until_open

          event_client.on_event(*SUBSCRIBE_EVENTS) do |data|
            Bidi2pdf.logger.debug "Received event: #{data["method"]}, params: #{data["params"]}"
          end
        end

        Bidi::Browser.new(client)
      end

      # rubocop: enable Metrics/AbcSize

      def create_client
        Bidi::Client.new(websocket_url).tap(&:start)
      end

      def create_new_session
        session_data = exec_api_call(session_request)
        Bidi2pdf.logger.debug "Session data: #{session_data}"

        value = session_data["value"]
        handle_error(value) if value.nil? || value["error"]

        session_id = value["sessionId"]
        ws_url = value["capabilities"]["webSocketUrl"]

        Bidi2pdf.logger.info "Created session with ID: #{session_id}"
        Bidi2pdf.logger.info "WebSocket URL: #{ws_url}"
        ws_url
      end

      def session_request
        session_chrome_args = chrome_args.dup
        session_chrome_args << "--headless" if @headless

        {
          "capabilities" => {
            "alwaysMatch" => {
              "browserName" => "chrome",
              "goog:chromeOptions" => { "args" => session_chrome_args },
              "goog:prerenderingDisabled" => true,
              "unhandledPromptBehavior" => { default: "ignore" },
              "acceptInsecureCerts" => true,
              "webSocketUrl" => true
            }
          }
        }
      end

      def exec_api_call(payload)
        response = Net::HTTP.post(session_uri, payload.to_json, "Content-Type" => "application/json")
        body = response.body
        code = response.code.to_i

        if code != 200
          log_api_error("Failed to create session", code, body)
          return build_error("Session creation failed", "Response code: #{code}")
        end

        JSON.parse(body)
      rescue StandardError => e
        error_type = error_category(e)
        build_error(error_type, "#{error_description(error_type)} #{e.message}", e.backtrace)
      end

      def log_api_error(message, code, body)
        Bidi2pdf.logger.error "#{message}. Response code: #{code}"
        Bidi2pdf.logger.error "Response body: #{body}"
      end

      def error_category(exception)
        case exception
        when Errno::ECONNREFUSED then "Connection refused"
        when JSON::ParserError then "Invalid JSON response"
        else "Unknown error"
        end
      end

      def error_description(type)
        {
          "Connection refused" => "Could not connect to the session URL:",
          "Invalid JSON response" => "Could not parse the response:",
          "Unknown error" => "An unknown error occurred:"
        }[type]
      end

      def build_error(error, message, backtrace = nil)
        {
          "value" => {
            "error" => error,
            "message" => message,
            "stacktrace" => backtrace&.join("\n")
          }.compact
        }
      end

      def handle_error(value)
        error = value["error"]
        return unless error

        msg = value["message"]
        trace = value["stacktrace"]

        Bidi2pdf.logger.error "Error: #{error} message: #{msg}"
        Bidi2pdf.logger.error "Stacktrace: #{trace}" if trace

        if msg =~ /probably user data directory is already in use/
          Bidi2pdf.logger.info "Container detected with headless-only support, ensure xvfb is started" unless @headless
          Bidi2pdf.logger.info "Check chromedriver permissions and --user-data-dir"
        end

        raise SessionNotStartedError,
              "Session not started. Check logs for more details. Error: #{error} message: #{msg}"
      end

      def cleanup
        @client&.close
        @client = @websocket_url = @browser = nil
      end
    end
  end
end
