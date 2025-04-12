# frozen_string_literal: true

module Bidi2pdf
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
