# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require_relative "client"
require_relative "browser"
require_relative "user_context"

# Represents a session for managing browser interactions and communication
# using the Bidi2pdf library. This class handles the setup, configuration,
# and execution of browser-related workflows, including session creation,
# WebSocket communication, and browser management.
#
# @example Creating and starting a session
#   session = Bidi2pdf::Bidi::Session.new(session_url: "http://example.com/session", headless: true)
#   session.start
#
# @example Retrieving user contexts
#   session.user_contexts
#
# @example Closing the session
#   session.close
#
# @param [String] session_url The URL for the session.
# @param [Boolean] headless Whether to run the browser in headless mode. Defaults to true.
# @param [Array<String>] chrome_args Additional Chrome arguments. Defaults to predefined arguments.
module Bidi2pdf
  module Bidi
    class Session
      # Events to subscribe to during the session.
      SUBSCRIBE_EVENTS = %w[script].freeze

      # Default Chrome arguments for the session.
      DEFAULT_CHROME_ARGS = %w[--disable-gpu --disable-popup-blocking --disable-hang-monitor].freeze

      # @return [URI] The URI of the session.
      attr_reader :session_uri

      # @return [Boolean] Whether the session has started.
      attr_reader :started

      # @return [Array<String>] The Chrome arguments for the session.
      attr_reader :chrome_args

      # Initializes a new session.
      #
      # @param [String] session_url The URL for the session.
      # @param [Boolean] headless Whether to run the browser in headless mode. Defaults to true.
      # @param [Array<String>] chrome_args Additional Chrome arguments. Defaults to predefined arguments.
      def initialize(session_url:, headless: true, chrome_args: DEFAULT_CHROME_ARGS)
        @session_uri = URI(session_url)
        @headless = headless
        @started = false
        @chrome_args = chrome_args.dup
      end

      # Starts the session and initializes the client.
      #
      # @raise [StandardError] If an error occurs during session start.
      def start
        return if started?

        @started = true
        client
      rescue StandardError => e
        @started = false
        raise e
      end

      # Returns the WebSocket client for the session.
      #
      # @return [Bidi2pdf::Bidi::Client, nil] The WebSocket client, or nil if the session is not started.
      def client
        @client ||= started? ? create_client : nil
      end

      # Returns the browser instance for the session.
      #
      # @return [Bidi2pdf::Bidi::Browser] The browser instance.
      def browser
        @browser ||= create_browser
      end

      # Closes the session and cleans up resources.
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
      ensure
        @started = false
      end

      # Retrieves user contexts for the session.
      def user_contexts
        send_cmd(Bidi2pdf::Bidi::Commands::GetUserContexts.new) { |resp| Bidi2pdf.logger.debug "User contexts: #{resp}" }
      end

      # Retrieves the status of the session.
      def status
        send_cmd(Bidi2pdf::Bidi::Commands::SessionStatus.new) { |resp| Bidi2pdf.logger.info "Session status: #{resp.inspect}" }
      end

      # Checks if the session has started.
      #
      # @return [Boolean] True if the session has started, false otherwise.
      def started?
        @started
      end

      # Retrieves the WebSocket URL for the session.
      #
      # @return [String] The WebSocket URL.
      def websocket_url
        return @websocket_url if @websocket_url

        @websocket_url = if %w[ws wss].include?(session_uri.scheme)
                           session_uri.to_s
                         else
                           create_new_session
                         end
      end

      private

      # Sends a command to the WebSocket client.
      #
      # @param [Object] command The command to send.
      # @yield [response] A block to handle the response.
      def send_cmd(command, &)
        client&.send_cmd_and_wait(command, &)
      end

      # Creates a new browser instance.
      #
      # @return [Bidi2pdf::Bidi::Browser] The browser instance.
      # rubocop:disable Metrics/AbcSize
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

      # rubocop:enable Metrics/AbcSize

      # Creates a new WebSocket client.
      #
      # @return [Bidi2pdf::Bidi::Client] The WebSocket client.
      def create_client
        Bidi::Client.new(websocket_url).tap(&:start)
      end

      # Creates a new session and retrieves the WebSocket URL.
      #
      # @return [String] The WebSocket URL.
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

      # Builds the session request payload.
      #
      # @return [Hash] The session request payload.
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

      # Executes an API call with the given payload.
      #
      # @param [Hash] payload The payload for the API call.
      # @return [Hash] The parsed response data.
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

      # Logs an API error.
      #
      # @param [String] message The error message.
      # @param [Integer] code The response code.
      # @param [String] body The response body.
      def log_api_error(message, code, body)
        Bidi2pdf.logger.error "#{message}. Response code: #{code}"
        Bidi2pdf.logger.error "Response body: #{body}"
      end

      # Determines the error category based on the exception.
      #
      # @param [Exception] exception The exception to categorize.
      # @return [String] The error category.
      def error_category(exception)
        case exception
        when Errno::ECONNREFUSED then "Connection refused"
        when JSON::ParserError then "Invalid JSON response"
        else "Unknown error"
        end
      end

      # Retrieves the error description for a given error type.
      #
      # @param [String] type The error type.
      # @return [String] The error description.
      def error_description(type)
        {
          "Connection refused" => "Could not connect to the session URL:",
          "Invalid JSON response" => "Could not parse the response:",
          "Unknown error" => "An unknown error occurred:"
        }[type]
      end

      # Builds an error response.
      #
      # @param [String] error The error type.
      # @param [String] message The error message.
      # @param [Array<String>, nil] backtrace The error backtrace.
      # @return [Hash] The error response.
      def build_error(error, message, backtrace = nil)
        {
          "value" => {
            "error" => error,
            "message" => message,
            "stacktrace" => backtrace&.join("\n")
          }.compact
        }
      end

      # Handles an error response from the session.
      #
      # @param [Hash] value The error response value.
      # @raise [SessionNotStartedError] If the session could not be started.
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

      # Cleans up resources associated with the session.
      def cleanup
        @client&.close
        @client = @websocket_url = @browser = nil
      end
    end
  end
end
