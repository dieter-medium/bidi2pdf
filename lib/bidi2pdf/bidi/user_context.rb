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
                          res = client.send_cmd_and_wait(Bidi2pdf::Bidi::Commands::BrowserCreateUserContext.new) do |response|
                            raise "Error creating user context: #{response.inspect}" if response["error"]

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
