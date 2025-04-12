# frozen_string_literal: true

require_relative "browser_tab"

module Bidi2pdf
  module Bidi
    # Represents a user context for managing browser interactions and cookies
    # using the Bidi2pdf library. This class provides methods for creating
    # user contexts, setting cookies, and creating browser windows.
    #
    # @example Creating a user context
    #   user_context = Bidi2pdf::Bidi::UserContext.new(client)
    #
    # @example Setting a cookie
    #   user_context.set_cookie(
    #     name: "session",
    #     value: "abc123",
    #     domain: "example.com",
    #     source_origin: "http://example.com"
    #   )
    #
    # @example Creating a browser window
    #   browser_window = user_context.create_browser_window
    #
    # @param [Object] client The WebSocket client for communication.
    class UserContext
      # @return [Object] The WebSocket client.
      attr_reader :client

      # Initializes a new user context.
      #
      # @param [Object] client The WebSocket client for communication.
      def initialize(client)
        @client = client
        @context_id = nil
      end

      # Retrieves the user context ID, creating it if it does not exist.
      #
      # @return [String] The user context ID.
      # @raise [RuntimeError] If an error occurs while creating the user context.
      def context_id
        @context_id ||= begin
                          res = client.send_cmd_and_wait(Bidi2pdf::Bidi::Commands::BrowserCreateUserContext.new) do |response|
                            raise "Error creating user context: #{response.inspect}" if response["error"]

                            response["result"]["userContext"]
                          end

                          Bidi2pdf.logger.debug "User context created: #{res.inspect}"

                          res
                        end
      end

      # Sets a cookie in the user context.
      #
      # @param [String] name The name of the cookie.
      # @param [String] value The value of the cookie.
      # @param [String] domain The domain for the cookie.
      # @param [String] source_origin The source origin for the cookie.
      # @param [String] path The path for the cookie. Defaults to "/".
      # @param [Boolean] secure Whether the cookie is secure. Defaults to true.
      # @param [Boolean] http_only Whether the cookie is HTTP-only. Defaults to false.
      # @param [String] same_site The SameSite attribute for the cookie. Defaults to "strict".
      # @param [Integer] ttl The time-to-live for the cookie in seconds. Defaults to 30.
      def set_cookie(
        name:,
        value:,
        domain:,
        source_origin:,
        path: "/",
        secure: true,
        http_only: false,
        same_site: "strict",
        ttl: 30
      )
        cmd = Bidi2pdf::Bidi::Commands::SetUsercontextCookie.new(
          user_context_id: context_id,
          source_origin: source_origin,
          name: name,
          value: value,
          domain: domain,
          path: path,
          secure: secure,
          http_only: http_only,
          same_site: same_site,
          ttl: ttl
        )

        client.send_cmd_and_wait(cmd) do |response|
          Bidi2pdf.logger.debug "Cookie set: #{response.inspect}"
        end
      end

      # Creates a new browser window in the user context.
      #
      # @return [BrowserTab] The newly created browser tab.
      def create_browser_window
        cmd = Bidi2pdf::Bidi::Commands::CreateWindow.new(user_context_id: context_id)

        client.send_cmd_and_wait(cmd) do |response|
          browsing_context_id = response["result"]["context"]

          BrowserTab.new(client, browsing_context_id, context_id)
        end
      end
    end
  end
end
