# frozen_string_literal: true

module Bidi2pdf
  # Represents a runner for managing browser sessions and executing tasks
  # using the Bidi2pdf library. This class handles the setup, configuration,
  # and execution of browser-related workflows, including navigation, cookie
  # management, and printing.
  #
  # @example Running a session
  #   session_runner = Bidi2pdf::SessionRunner.new(
  #     session: session,
  #     url: "http://example.com",
  #     inputfile: "input.html",
  #     output: "output.pdf",
  #     cookies: { "key" => "value" },
  #     headers: { "Authorization" => "Bearer token" },
  #     auth: { username: "user", password: "pass" },
  #     wait_window_loaded: true,
  #     wait_network_idle: true,
  #     print_options: { landscape: true },
  #     network_log_format: :json
  #   )
  #   session_runner.run
  #
  # @param [Object] session The browser session object to use.
  # @param [String, nil] url The URL to navigate to in the browser session.
  # @param [String, nil] inputfile The path to the input file to be processed if no URL is provided.
  # @param [String, nil] output The path to the output file to be generated.
  # @param [Hash] cookies A hash of cookies to set in the browser session. Defaults to an empty hash.
  # @param [Hash] headers A hash of HTTP headers to include in the browser session. Defaults to an empty hash.
  # @param [Hash, nil] auth Authentication credentials (e.g., username and password). Defaults to an empty hash.
  # @param [Boolean] wait_window_loaded Whether to wait for the window to fully load. Defaults to false.
  # @param [Boolean] wait_network_idle Whether to wait for the network to become idle. Defaults to false.
  # @param [Hash] print_options Options for printing the page. Defaults to an empty hash.
  # @param [Symbol] network_log_format The format for network logs. Defaults to :console.
  class SessionRunner
    # rubocop: disable Metrics/ParameterLists
    def initialize(session:, url:, inputfile:, output:, cookies: {}, headers: {}, auth: {}, wait_window_loaded: false,
                   wait_network_idle: false, print_options: {}, network_log_format: :console)
      @session = session
      @url = url
      @inputfile = inputfile
      @output = output
      @cookies = cookies || {}
      @headers = headers || {}
      @auth = auth || {}
      @wait_window_loaded = wait_window_loaded
      @wait_network_idle = wait_network_idle
      @print_options = print_options || {}
      @network_log_format = network_log_format
    end

    # rubocop: enable Metrics/ParameterLists

    def run
      @session.start
      @session.client.on_close { Bidi2pdf.logger.info "WebSocket closed" }

      setup_browser
      run_flow
    end

    private

    def setup_browser
      browser = @session.browser
      user_context = browser.create_user_context

      window = user_context.create_browser_window
      tab = window.create_browser_tab

      @window = window
      @tab = tab

      add_cookies(tab)

      add_headers
      add_basic_auth
    end

    def add_cookies(tab)
      @cookies.each do |name, value|
        tab.set_cookie(
          name: name,
          value: value,
          domain: domain,
          secure: uri.scheme == "https"
        )
      end
    end

    def add_headers
      @headers.each do |name, value|
        @tab.add_headers(
          url_patterns: url_patterns,
          headers: [{ name: name, value: value }]
        )
      end
    end

    def add_basic_auth
      return unless @auth[:username] && @auth[:password]

      @tab.basic_auth(
        url_patterns: url_patterns,
        username: @auth[:username],
        password: @auth[:password]
      )
    end

    # rubocop: disable Metrics/AbcSize
    def run_flow
      @session.status
      @session.user_contexts

      if @url
        @tab.navigate_to(@url)
      else
        Bidi2pdf.logger.info "Loading HTML file #{@inputfile}"
        data = File.read(@inputfile)
        @tab.render_html_content(data)
      end

      if @wait_network_idle
        Bidi2pdf.logger.info "Waiting for network idle"
        @tab.wait_until_network_idle
      end

      log_output_file = (@output || "report").sub(/\.pdf$/, "-network.pdf") # only need, when html output
      @tab.log_network_traffic format: @network_log_format, output: log_output_file

      if @wait_window_loaded
        Bidi2pdf.logger.info "Waiting for window to be loaded"
        @tab.execute_script <<-EOF_SCRIPT
            new Promise(resolve => { const check = () => window.loaded ? resolve('done') : setTimeout(check, 100); check(); });
        EOF_SCRIPT
      end

      @tab.print(@output, print_options: @print_options)
    ensure
      @tab.close
      @window.close
    end

    # rubocop: enable Metrics/AbcSize

    def uri
      @uri ||= URI(@url)
    end

    def domain
      uri.host
    end

    def source_origin
      origin = "#{uri.scheme}://#{uri.host}"
      origin += ":#{uri.port}" unless [80, 443].include?(uri.port)
      origin
    end

    def url_patterns
      [
        {
          type: "pattern",
          protocol: uri.scheme,
          hostname: uri.host,
          port: uri.port.to_s
        }
      ]
    end
  end
end
