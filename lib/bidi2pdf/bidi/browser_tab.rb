# frozen_string_literal: true

require "base64"

require_relative "network_events"
require_relative "print_parameters_validator"
require_relative "auth_interceptor"
require_relative "add_headers_interceptor"

module Bidi2pdf
  module Bidi
    class BrowserTab
      attr_reader :client, :browsing_context_id, :user_context_id, :tabs, :network_events, :open

      def initialize(client, browsing_context_id, user_context_id)
        @client = client
        @browsing_context_id = browsing_context_id
        @user_context_id = user_context_id
        @tabs = []
        @network_events = NetworkEvents.new browsing_context_id
        @open = true
      end

      def create_browser_tab
        client.send_cmd_and_wait("browsingContext.create", {
          type: "tab",
          userContext: @user_context_id
        }) do |response|
          tab_browsing_context_id = response["result"]["context"]

          BrowserTab.new(client, tab_browsing_context_id, user_context_id).tap do |tab|
            tabs << tab
            Bidi2pdf.logger.debug "Created new browser tab: #{tab.inspect}"
          end
        end
      end

      def set_cookie(
        name:,
        value:,
        domain:,
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
            type: "context",
            context: browsing_context_id
          }
        }) do |response|
          Bidi2pdf.logger.debug "Cookie set: #{response.inspect}"
        end
      end

      def add_headers(
        headers:,
        url_patterns:
      )
        AddHeadersInterceptor.new(
          context: browsing_context_id,
          url_patterns: url_patterns,
          headers: headers
        ).tap { |interceptor| interceptor.register_with_client(client: client) }
      end

      def basic_auth(username:, password:, url_patterns:)
        AuthInterceptor.new(
          context: browsing_context_id,
          url_patterns: url_patterns,
          username: username, password: password
        ).tap { |interceptor| interceptor.register_with_client(client: client) }
      end

      def open_page(url)
        client.on_event("network.responseStarted", "network.responseCompleted", "network.fetchError",
                        &network_events.method(:handle_event))

        client.send_cmd_and_wait("browsingContext.navigate", {
          url: url,
          context: browsing_context_id,
          wait: "complete"
        }) do |response|
          Bidi2pdf.logger.debug "Navigated to page url: #{url} response: #{response}"
        end
      end

      def execute_script(script)
        client.send_cmd_and_wait("script.evaluate", {
          expression: script,
          target: {
            context: browsing_context_id
          },
          awaitPromise: true
        }) do |response|
          Bidi2pdf.logger.debug "Script Result: #{response.inspect}"

          response["result"]
        end
      end

      def wait_until_all_finished(timeout: 10, poll_interval: 0.1)
        network_events.wait_until_all_finished(timeout: timeout, poll_interval: poll_interval)
      end

      def close
        return unless open

        close_tabs
        remove_event_listeners
        close_context

        @open = false
      end

      # rubocop:disable Metrics/AbcSize
      def print(outputfile, print_options: { background: true })
        PrintParametersValidator.validate!(print_options)

        cmd_params = (print_options || {}).merge(context: browsing_context_id)

        client.send_cmd_and_wait("browsingContext.print", cmd_params) do |response|
          if response["result"]
            pdf_base64 = response["result"]["data"]

            if outputfile
              File.binwrite(outputfile, Base64.decode64(pdf_base64))
              Bidi2pdf.logger.info "PDF saved as '#{outputfile}'."
            else
              Bidi2pdf.logger.info "PDF generated successfully."
            end

            return pdf_base64 unless outputfile
          else
            Bidi2pdf.logger.error "Error printing: #{response}"
          end
        end
      end

      # rubocop:enable Metrics/AbcSize

      private

      def close_context
        client.send_cmd_and_wait("browsingContext.close", { context: browsing_context_id }) do |response|
          Bidi2pdf.logger.debug "Browsing context closed: #{response}"
        end
      end

      def remove_event_listeners
        Bidi2pdf.logger.debug "Network events: #{network_events.all_events.map(&:to_s)}"

        client.remove_event_listener "network.responseStarted", "network.responseCompleted", "network.fetchError",
                                     &network_events.method(:handle_event)
      end

      def close_tabs
        tabs.each do |tab|
          tab.close
          Bidi2pdf.logger.debug "Closed tab: #{tab.browsing_context_id}"
        end
      end
    end
  end
end
