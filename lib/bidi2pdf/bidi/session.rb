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
      SUBSCRIBE_EVENTS = [
        "browsingContext",
        "network",
        "log",
        "script",
        "goog:cdp.Debugger.scriptParsed",
        "goog:cdp.CSS.styleSheetAdded",
        "goog:cdp.Runtime.executionContextsCleared",
        # Tracing
        "goog:cdp.Tracing.tracingComplete",
        "goog:cdp.Network.requestWillBeSent",
        "goog:cdp.Debugger.scriptParsed",
        "goog:cdp.Page.screencastFrame"
      ].freeze

      attr_reader :port, :websocket_url

      def initialize(port, headless: true)
        @port = port
        @headless = headless
        @client = nil
        @browser = nil
        @websocket_url = nil
      end

      def start
        client
      end

      def client
        @client ||= create_client
      end

      def close
        client&.send_cmd_and_wait("session.end", {}) do |response|
          Bidi2pdf.logger.debug "Session ended: #{response}"
          @client = nil
          @websocket_url = nil
          @browser = nil
        end
      end

      def browser
        @browser ||= create_browser
      end

      def user_contexts
        client&.send_cmd_and_wait("browser.getUserContexts", {}) do |response|
          Bidi2pdf.logger.debug "User contexts: #{response}"
        end
      end

      def status
        client&.send_cmd_and_wait("session.status", {}) do |response|
          Bidi2pdf.logger.info "Session status: #{response.inspect}"
        end
      end

      private

      def create_browser
        start

        @client.start
        @client.wait_until_open

        Bidi2pdf.logger.info "Subscribing to events"

        event_client = Bidi::Client.new(websocket_url).tap(&:start)
        event_client.wait_until_open

        event_client.on_event(*SUBSCRIBE_EVENTS) do |data|
          Bidi2pdf.logger.debug "Received event: #{data["method"]}, params: #{data["params"]}"
        end

        Bidi::Browser.new(@client)
      end

      # rubocop: disable Metrics/AbcSize
      def create_client
        uri = URI("http://localhost:#{port}/session")
        args = %w[
          --disable-gpu
          --disable-popup-blocking
          --disable-hang-monitor
        ]

        args << "--headless" if @headless

        session_request = {
          "capabilities" => {
            "alwaysMatch" => {
              "browserName" => "chrome",
              "goog:chromeOptions" => {
                "args" => args
              },
              "goog:prerenderingDisabled" => true,
              "unhandledPromptBehavior" => {
                default: "ignore"
              },
              "acceptInsecureCerts" => true,
              "webSocketUrl" => true
            }
          }
        }
        response = Net::HTTP.post(uri, session_request.to_json, "Content-Type" => "application/json")
        session_data = JSON.parse(response.body)

        Bidi2pdf.logger.debug "Session data: #{session_data}"

        session_id = session_data["value"]["sessionId"]
        @websocket_url = session_data["value"]["capabilities"]["webSocketUrl"]

        Bidi2pdf.logger.info "Created session with ID: #{session_id}"
        Bidi2pdf.logger.info "WebSocket URL: #{@websocket_url}"

        Bidi::Client.new(@websocket_url).tap(&:start)
      end

      # rubocop: enable Metrics/AbcSize
    end
  end
end
