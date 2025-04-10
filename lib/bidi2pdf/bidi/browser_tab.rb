# frozen_string_literal: true

require "base64"

require_relative "network_events"
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
        cmd = Bidi2pdf::Bidi::Commands::CreateTab.new(user_context_id: user_context_id)
        client.send_cmd_and_wait(cmd) do |response|
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
        cmd = Bidi2pdf::Bidi::Commands::SetTabCookie.new(
          browsing_context_id: browsing_context_id,
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

        cmd = Bidi2pdf::Bidi::Commands::BrowsingContextNavigate.new url: url, context: browsing_context_id

        client.send_cmd_and_wait(cmd) do |response|
          Bidi2pdf.logger.debug "Navigated to page url: #{url} response: #{response}"
        end
      end

      def execute_script(script)
        cmd = Bidi2pdf::Bidi::Commands::ScriptEvaluate.new context: browsing_context_id, expression: script
        client.send_cmd_and_wait(cmd) do |response|
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

      # rubocop: disable Metrics/AbcSize, Metrics/PerceivedComplexity
      def print(outputfile = nil, print_options: { background: true }, &block)
        cmd = Bidi2pdf::Bidi::Commands::BrowsingContextPrint.new context: browsing_context_id, print_options: print_options

        client.send_cmd_and_wait(cmd) do |response|
          if response["result"]
            pdf_base64 = response["result"]["data"]

            if outputfile
              raise PrintError, "Folder does not exist: #{File.dirname(outputfile)}" unless File.directory?(File.dirname(outputfile))

              File.binwrite(outputfile, Base64.decode64(pdf_base64))
              Bidi2pdf.logger.info "PDF saved as '#{outputfile}'."
            else
              Bidi2pdf.logger.info "PDF generated successfully."
            end

            block.call(pdf_base64) if block_given?

            return pdf_base64 unless outputfile || block_given?
          else
            Bidi2pdf.logger.error "Error printing: #{response}"
          end
        end
      end

      # rubocop: enable Metrics/AbcSize, Metrics/PerceivedComplexity

      private

      def close_context
        that = self
        cmd = Bidi2pdf::Bidi::Commands::BrowsingContextClose.new context: browsing_context_id
        client.send_cmd_and_wait(cmd) do |response|
          Bidi2pdf.logger.info "Browsing context closed: #{that.browsing_context_id} #{response}"
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
