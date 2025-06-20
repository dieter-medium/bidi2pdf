# frozen_string_literal: true

require "base64"

require_relative "network_events"
require_relative "logger_events"
require_relative "navigation_failed_events"
require_relative "auth_interceptor"
require_relative "add_headers_interceptor"
require_relative "js_logger_helper"

# Represents a browser tab for managing interactions and communication
# using the Bidi2pdf library. This class provides methods for creating
# browser tabs, managing cookies, navigating to URLs, executing scripts,
# and handling network events.
#
# @example Creating a browser tab
#   browser_tab = Bidi2pdf::Bidi::BrowserTab.new(client, browsing_context_id, user_context_id)
#   browser_tab.create_browser_tab
#
# @example Navigating to a URL
#   browser_tab.navigate_to("http://example.com")
#
# @example Setting a cookie
#   browser_tab.set_cookie(
#     name: "session",
#     value: "abc123",
#     domain: "example.com"
#   )
#
# @param [Object] client The WebSocket client for communication.
# @param [String] browsing_context_id The ID of the browsing context.
# @param [String] user_context_id The ID of the user context.
module Bidi2pdf
  module Bidi
    # Represents a browser tab for managing interactions and communication
    # using the Bidi2pdf library. This class provides methods for creating
    # browser tabs, managing cookies, navigating to URLs, executing scripts,
    # handling network events, and general tab lifecycle management.
    #
    class BrowserTab
      include JsLoggerHelper

      # @return [Object] The WebSocket client.
      attr_reader :client

      # @return [String] The browsing context ID.
      attr_reader :browsing_context_id

      # @return [String] The user context ID.
      attr_reader :user_context_id

      # @return [Array<BrowserTab>] The list of tabs.
      attr_reader :tabs

      # @return [NetworkEvents] The network events handler.
      attr_reader :network_events

      # @return [Boolean] Whether the tab is open.
      attr_reader :open

      # @return [LoggerEvents] The logger events handler.
      attr_reader :logger_events

      # @return [NavigationFailedEvents] The navigation failed events handler.
      attr_reader :navigation_failed_events

      # Initializes a new browser tab.
      #
      # @param [Object] client The WebSocket client for communication.
      # @param [String] browsing_context_id The ID of the browsing context.
      # @param [String] user_context_id The ID of the user context.
      def initialize(client, browsing_context_id, user_context_id)
        @client = client
        @browsing_context_id = browsing_context_id
        @user_context_id = user_context_id
        @tabs = []
        @network_events = NetworkEvents.new browsing_context_id
        @logger_events = LoggerEvents.new browsing_context_id
        @navigation_failed_events = NavigationFailedEvents.new browsing_context_id
        @open = true
      end

      # Creates a new browser tab.
      #
      # @return [BrowserTab] The newly created browser tab.
      def create_browser_tab
        cmd = Bidi2pdf::Bidi::Commands::CreateTab.new(user_context_id: user_context_id)
        client.send_cmd_and_wait(cmd) do |response|
          tab_browsing_context_id = response["result"]["context"]

          BrowserTab.new(client, tab_browsing_context_id, user_context_id).tap do |tab|
            tabs << tab
            Bidi2pdf.logger.debug1 "Created new browser tab: #{tab.inspect}"
          end
        end
      end

      # Sets a cookie in the browser tab.
      #
      # @param [String] name The name of the cookie.
      # @param [String] value The value of the cookie.
      # @param [String] domain The domain for the cookie.
      # @param [String] path The path for the cookie. Defaults to "/".
      # @param [Boolean] secure Whether the cookie is secure. Defaults to true.
      # @param [Boolean] http_only Whether the cookie is HTTP-only. Defaults to false.
      # @param [String] same_site The SameSite attribute for the cookie. Defaults to "strict".
      # @param [Integer] ttl The time-to-live for the cookie in seconds. Defaults to 30.
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
          Bidi2pdf.logger.debug1 "Cookie set: #{response.inspect}"
        end
      end

      # Adds headers to requests in the browser tab.
      #
      # @param [Hash] headers The headers to add.
      # @param [Array<String>] url_patterns The URL patterns to match.
      # @return [AddHeadersInterceptor] The interceptor instance.
      def add_headers(
        headers:,
        url_patterns:
      )
        @header_interceptor = AddHeadersInterceptor.new(
          context: browsing_context_id,
          url_patterns: url_patterns,
          headers: headers
        ).tap { |interceptor| interceptor.register_with_client(client: client) }
      end

      # Configures basic authentication for requests in the browser tab.
      #
      # @param [String] username The username for authentication.
      # @param [String] password The password for authentication.
      # @param [Array<String>] url_patterns The URL patterns to match.
      # @return [AuthInterceptor] The interceptor instance.
      def basic_auth(username:, password:, url_patterns:)
        @basic_auth_interceptor = AuthInterceptor.new(
          context: browsing_context_id,
          url_patterns: url_patterns,
          username: username, password: password
        ).tap { |interceptor| interceptor.register_with_client(client: client) }
      end

      # Navigates the browser tab to a specified URL.
      #
      # This method registers necessary event listeners and sends a navigation
      # command to the browser tab, instructing it to load the specified URL.
      # It validates that the URL is properly formatted before attempting navigation.
      #
      # @param [String] url The URL to navigate to.
      # @raise [NavigationError] If the URL is invalid or improperly formatted.
      # @example
      #   browser_tab.navigate_to("https://example.com")
      def navigate_to(url)
        begin
          URI.parse(url)
        rescue URI::InvalidURIError => e
          raise NavigationError, "Invalid URL: #{url} - #{e.message}"
        end

        Bidi2pdf.notification_service.instrument("navigate_to.bidi2pdf", url: url) do
          navigate_with_listeners url
        end
      end

      # Renders HTML content in the browser tab.
      #
      # @param [String] html_content The HTML content to render.
      def render_html_content(html_content)
        Bidi2pdf.notification_service.instrument("render_html_content.bidi2pdf", url: "data:text/html") do |instrumentation_payload|
          base64_encoded = Base64.strict_encode64(html_content)

          instrumentation_payload[:data] = base64_encoded

          data_url = "data:text/html;charset=utf-8;base64,#{base64_encoded}"

          navigate_with_listeners data_url
        end
      end

      # Executes a script in the browser tab.
      #
      # This method allows you to execute JavaScript code within the context of the browser tab.
      # Optionally, the script can be wrapped in a JavaScript Promise to handle asynchronous operations.
      #
      # @param [String] script The JavaScript code to execute.
      #   - This can be any valid JavaScript code that you want to run in the browser tab.
      # @param [Boolean] wrap_in_promise Whether to wrap the script in a Promise. Defaults to false.
      #   - If true, the script will be wrapped in a Promise to handle asynchronous execution.
      #   - Use this option when the script involves asynchronous operations like network requests.
      #     You can use the predefined variable result to store the result of the script.
      # @return [Object] The result of the script execution.
      #   - If the script executes successfully, the result of the last evaluated expression is returned.
      #   - If the script fails, an error or exception details may be returned.
      def execute_script(script, wrap_in_promise: false)
        Bidi2pdf.notification_service.instrument("execute_script.bidi2pdf") do
          if wrap_in_promise
            script = <<~JS
              new Promise((resolve, reject) => {
                try {
                  let result;

                  #{script}

                  resolve(result);
                } catch (error) {
                  reject(error);
                }
              });
            JS
          end

          cmd = Bidi2pdf::Bidi::Commands::ScriptEvaluate.new context: browsing_context_id, expression: script
          client.send_cmd_and_wait(cmd) do |response|
            Bidi2pdf.logger.debug2 "Script Result: #{response.inspect}"

            response["result"]
          end
        end
      end

      # Injects a JavaScript script element into the page, either from a URL or with inline content.
      #
      # @param [String, nil] url The URL of the script to load (optional).
      # @param [String, nil] content The JavaScript content to inject (optional).
      # @param [String, nil] id The ID attribute for the script element (optional).
      # @return [Object] The result from the script creation promise.
      def inject_script(url: nil, content: nil, id: nil)
        script_code = generate_script_element_code(url: url, content: content, id: id)
        response = execute_script(script_code)

        if response
          if response["type"] == "exception"
            handle_injection_exception(response, url, ScriptInjectionError)
          elsif response["type"] == "success"
            Bidi2pdf.logger.debug1 "Script injected successfully: #{response.inspect}"
            response
          else
            Bidi2pdf.logger.warn "Script injected unknown state: #{response.inspect}"
            response
          end
        else
          Bidi2pdf.logger.error "Failed to inject script: #{url || content}"
          raise ScriptInjectionError, "Failed to inject script: #{url || content}"
        end
      end

      # Injects a CSS style element into the page, either from a URL or with inline content.
      #
      # @param [String, nil] url The URL of the stylesheet to load (optional).
      # @param [String, nil] content The CSS content to inject (optional).
      # @param [String, nil] id The ID attribute for the style element (optional).
      # @return [Object] The result from the style creation promise.
      def inject_style(url: nil, content: nil, id: nil)
        style_code = generate_style_element_code(url: url, content: content, id: id)
        response = execute_script(style_code)

        if response
          if response["type"] == "exception"
            handle_injection_exception(response, url, StyleInjectionError)
          elsif response["type"] == "success"
            Bidi2pdf.logger.debug1 "Style injected successfully: #{response.inspect}"
            response
          else
            Bidi2pdf.logger.warn "Style injection unknown state: #{response.inspect}"
            response
          end
        else
          Bidi2pdf.logger.error "Failed to inject style: #{url || content}"
          raise StyleInjectionError, "Failed to inject style: #{url || content}"
        end
      end

      # Waits until the network is idle in the browser tab.
      #
      # @param [Integer] timeout The timeout duration in seconds. Defaults to 10.
      # @param [Float] poll_interval The polling interval in seconds. Defaults to 0.1.
      def wait_until_network_idle(timeout: 10, poll_interval: 0.1)
        Bidi2pdf.notification_service.instrument("network_idle.bidi2pdf") do |instrumentation_payload|
          network_events.wait_until_network_idle(timeout: timeout, poll_interval: poll_interval)

          instrumentation_payload[:requests] = network_events.all_events.dup
        end
      end

      # Waits until the page is fully loaded in the browser tab.
      #
      # This method executes a JavaScript script that checks if the page
      # has finished loading.
      #
      # @param [String] check_script The JavaScript code to check if the page is loaded.
      #   - Defaults to a script that polls the `window.loaded` property.
      # @return [Object] The result of the script execution.
      #   - If the page is loaded successfully, the Promise resolves with the value `'done'`.
      #   - If the script fails, an error or exception details may be returned.
      def wait_until_page_loaded(check_script: nil)
        check_script ||= <<~JS
          new Promise(resolve => { const check = () => window.loaded ? resolve('done') : setTimeout(check, 100); check(); });
        JS

        Bidi2pdf.notification_service.instrument("page_loaded.bidi2pdf") do
          execute_script check_script
        end
      end

      # Logs network traffic in the browser tab.
      #
      # @param [Symbol] format The format for logging (:console or :pdf). Defaults to :console.
      # @param [String, nil] output The output file for PDF logging. Defaults to nil.
      # @param [Hash] print_options Options for printing. Defaults to { background: true }.
      # @yield [pdf_base64] A block to handle the PDF content.
      def log_network_traffic(format: :console, output: nil, print_options: { background: true }, &)
        format = format.to_sym

        if format == :console
          network_events.log_network_traffic format: :console
        elsif format == :pdf
          html_content = network_events.log_network_traffic format: :html

          return unless html_content

          logging_tab = create_browser_tab

          logging_tab.render_html_content(html_content)
          logging_tab.wait_until_network_idle

          logging_tab.print(output, print_options: print_options, &)

          logging_tab.close
        end
      end

      # Closes the browser tab and its associated resources.
      def close
        return unless open

        close_tabs
        remove_event_listeners
        close_context

        @open = false
      end

      # Prints the content of the browser tab.
      #
      # @param [String, nil] outputfile The output file for the PDF. Defaults to nil.
      # @param [Hash] print_options Options for printing. Defaults to { background: true }.
      # @yield [pdf_base64] A block to handle the PDF content.
      # @return [String, nil] The base64-encoded PDF content, or nil if outputfile or block is provided.
      # rubocop:disable Metrics/AbcSize, Metrics/PerceivedComplexity
      def print(outputfile = nil, print_options: { background: true }, &block)
        Bidi2pdf.notification_service.instrument("print.bidi2pdf") do |instrumentation_payload|
          cmd, extractor = build_command_and_extractor(print_options)

          instrumentation_payload[:cmd] = cmd

          client.send_cmd_and_wait(cmd) do |response|
            if response["result"]
              pdf_base64 = extractor.call response

              instrumentation_payload[:pdf_base64] = pdf_base64

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
      end

      # rubocop:enable Metrics/AbcSize, Metrics/PerceivedComplexity

      private

      def build_command_and_extractor(print_options)
        cmd_type = (print_options.delete(:cmd_type) || :bidi).to_sym

        if cmd_type == :bidi
          cmd = Bidi2pdf::Bidi::Commands::BrowsingContextPrint.new(
            context: browsing_context_id,
            print_options: print_options
          )
          extractor = ->(response) { response.dig("result", "data") }
        else
          cmd = Bidi2pdf::Bidi::Commands::PagePrint.new(
            cdp_session: cdp_session,
            print_options: print_options
          )
          extractor = ->(response) { response.dig("result", "result", "data") }
        end

        [cmd, extractor]
      end

      def cdp_session
        @cdp_session ||= begin
                           cmd = Bidi2pdf::Bidi::Commands::CdpGetSession.new context: browsing_context_id
                           client.send_cmd_and_wait(cmd) do |response|
                             Bidi2pdf.logger.debug "CDP session: #{response.inspect}"
                             response["result"]["session"]
                           end
                         end
      end

      def navigate_with_listeners(url)
        register_event_listeners

        cmd = Bidi2pdf::Bidi::Commands::BrowsingContextNavigate.new url: url, context: browsing_context_id

        client.send_cmd_and_wait(cmd) do |response|
          Bidi2pdf.logger.debug "Navigated to page url: #{url} response: #{response}"
        end
      rescue Bidi2pdf::CmdError => e
        msg = e.response["message"]
        case msg
        when /^net::ERR_INVALID_AUTH_CREDENTIALS/
          raise NavigationAuthError.new(url, msg)
        when /^net::ERR_NAME_NOT_RESOLVED/
          raise NavigationDNSError.new(url, msg)
        when /^net::/
          raise NavigationError, "Connection error: #{url} #{msg}"
        else
          raise e
        end
      end

      def register_event_listeners
        return if @event_handlers_registered

        @event_handlers_registered = true
        @listener_refs ||= {}

        @listener_refs[:network] = client.on_event("network.beforeRequestSent", "network.responseStarted", "network.responseCompleted", "network.fetchError",
                                                   &network_events.method(:handle_event))

        @listener_refs[:logger] = client.on_event("log.entryAdded", &logger_events.method(:handle_event))

        @listener_refs[:navigation_failed] = client.on_event("browsingContext.navigationFailed", &navigation_failed_events.method(:handle_event))
      end

      def handle_injection_exception(response, url, exception_class)
        exception = response["exceptionDetails"]
        error_text = exception["text"]
        line = exception["lineNumber"]
        column = exception["columnNumber"]

        # Extract stack trace information if available
        stack_info = format_stack_trace(exception["stackTrace"])
        script_source = url ? "URL: #{url}" : "inline content"
        error_message = "Script injection failed (#{script_source}): #{error_text} at line #{line}:#{column}\n#{stack_info}"

        Bidi2pdf.logger.error error_message
        raise exception_class, error_message
      end

      # Generates JavaScript code for creating a script element with given parameters.
      #
      # @param [String, nil] url The URL of the script to load (optional).
      # @param [String, nil] content The JavaScript content for the script (optional).
      # @param [String, nil] id The ID attribute for the script element (optional).
      # @return [String] JavaScript code that creates a script element.
      def generate_script_element_code(url: nil, content: nil, id: nil)
        js_src_part = ""
        js_src_part = <<~SRC if url
          script.src = '#{url}';
          script.addEventListener(
            'load',
            () => {
              resolve(script);
            },
            {once: true},
          );
        SRC

        <<~JS
          new Promise((resolve, reject) => {
            const script = document.createElement('script');
            script.type = 'text/javascript';

            #{"script.text = #{content.to_json};" if content}

            script.addEventListener(
              'error',
              event => {
                reject(new Error(event.message ?? 'Could not load script'));
              },
              {once: true},
            );

            #{"script.id = '#{id}';" if id}
            #{js_src_part}

            document.head.appendChild(script);

            #{"resolve(script);" unless url}
          });
        JS
      end

      # Generates JavaScript code for creating a style element with given parameters.
      #
      # @param [String, nil] url The URL of the stylesheet to load (optional).
      # @param [String, nil] content The CSS content for the style (optional).
      # @param [String, nil] id The ID attribute for the style element (optional).
      # @return [String] JavaScript code that creates a style element.
      def generate_style_element_code(url: nil, content: nil, id: nil)
        if url
          # For external stylesheets, create a link element
          <<~JS
            new Promise((resolve, reject) => {
              const link = document.createElement('link');
              link.rel = 'stylesheet';
              link.type = 'text/css';
              link.href = '#{url}';
            #{"  "}
              #{"link.id = '#{id}';" if id}
            #{"  "}
              link.addEventListener(
                'load',
                () => {
                  resolve(link);
                },
                {once: true}
              );
            #{"  "}
              link.addEventListener(
                'error',
                event => {
                  reject(new Error(event.message ?? 'Could not load stylesheet'));
                },
                {once: true}
              );
            #{"  "}
              document.head.appendChild(link);
            });
          JS
        else
          # For inline styles, create a style element
          <<~JS
            new Promise((resolve, reject) => {
              try {
                const style = document.createElement('style');
                style.type = 'text/css';
            #{"    "}
                #{"style.id = '#{id}';" if id}
            #{"    "}
                #{"style.textContent = #{content.to_json};" if content}
            #{"    "}
                document.head.appendChild(style);
                resolve(style);
              } catch (error) {
                reject(error);
              }
            });
          JS
        end
      end

      # Closes the browsing context.
      def close_context
        that = self
        cmd = Bidi2pdf::Bidi::Commands::BrowsingContextClose.new context: browsing_context_id
        client.send_cmd_and_wait(cmd) do |response|
          Bidi2pdf.logger.info "Browsing context closed: #{that.browsing_context_id} #{response}"
        end
      end

      # Removes event listeners for the browser tab.
      # rubocop:disable Metrics/AbcSize
      def remove_event_listeners
        return if @listener_refs.nil? || @listener_refs.empty?

        Bidi2pdf.logger.debug2 "Network events: #{network_events.all_events.map(&:to_s)}"

        client.remove_event_listener("network.beforeRequestSent", "network.responseStarted", "network.responseCompleted", "network.fetchError",
                                     @listener_refs[:network])

        client.remove_event_listener("log.entryAdded", @listener_refs[:logger])

        @header_interceptor&.unregister_with_client(client: client)
        @basic_auth_interceptor&.unregister_with_client(client: client)

        @header_interceptor = nil
        @basic_auth_interceptor = nil
        @listener_refs = {}
      end

      # rubocop:enable Metrics/AbcSize

      # Closes all tabs associated with the browser tab.
      def close_tabs
        tabs.each do |tab|
          tab.close
          Bidi2pdf.logger.debug "Closed tab: #{tab.browsing_context_id}"
        end
      end
    end
  end
end
