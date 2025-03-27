# frozen_string_literal: true

require_relative "browser_tab"

module Bidi2pdf
  module Bidi
    class UserContext
      attr_reader :client

      def initialize(client)
        @client = client
        @context_id = nil
      end

      def context_id
        @context_id ||= begin
          res = client.send_cmd_and_wait("browser.createUserContext", {}) do |response|
            response["result"]["userContext"]
          end

          Bidi2pdf.logger.debug "User context created: #{res.inspect}"

          res
        end
      end

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
        expiry = Time.now.to_i + ttl
        client.send_cmd_and_wait("storage.setCookie", {
          cookie: {
            name: name,
            value: {
              type: "string",
              value: value
            },
            domain: domain,
            path: path,
            secure: secure,
            httpOnly: http_only,
            sameSite: same_site,
            expiry: expiry
          },
          partition: {
            type: "storageKey",
            userContext: context_id,
            sourceOrigin: source_origin
          }
        }) do |response|
          Bidi2pdf.logger.debug "Cookie set: #{response.inspect}"
        end
      end

      def create_browser_window
        client.send_cmd_and_wait("browsingContext.create", {
          type: "window",
          userContext: context_id
        }) do |response|
          browsing_context_id = response["result"]["context"]

          BrowserTab.new(client, browsing_context_id, context_id)
        end
      end
    end
  end
end
