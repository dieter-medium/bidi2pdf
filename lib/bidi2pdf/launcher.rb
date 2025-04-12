# frozen_string_literal: true

require_relative "chromedriver_manager"
require_relative "session_runner"
require_relative "bidi/session"

module Bidi2pdf
  # Represents a launcher for managing browser sessions and executing tasks
  # using the Bidi2pdf library. This class handles the setup and teardown
  # of browser sessions, as well as the execution of tasks within those sessions.
  #
  # @example Launching a session
  #   launcher = Bidi2pdf::Launcher.new(
  #     url: "http://example.com",
  #     inputfile: "input.pdf",
  #     output: "output.pdf",
  #     cookies: [],
  #     headers: {},
  #     auth: nil,
  #     headless: true
  #   )
  #   launcher.launch
  #   launcher.stop
  #
  # @param [String] url The URL to navigate to in the browser session.
  # @param [String] inputfile The path to the input file to be processed.
  # @param [String] output The path to the output file to be generated.
  # @param [Array<Hash>] cookies An array of cookies to set in the browser session.
  # @param [Hash] headers A hash of HTTP headers to include in the browser session.
  # @param [Hash, nil] auth Authentication credentials (e.g., username and password).
  # @param [Boolean] headless Whether to run the browser in headless mode. Defaults to true.
  # @param [Integer] port The port to use for the browser session. Defaults to 0.
  # @param [Boolean] wait_window_loaded Whether to wait for the window to fully load. Defaults to false.
  # @param [Boolean] wait_network_idle Whether to wait for the network to become idle. Defaults to false.
  # @param [Hash] print_options Options for printing the page. Defaults to an empty hash.
  # @param [String, nil] remote_browser_url The URL of a remote browser to connect to. Defaults to nil.
  # @param [Symbol] network_log_format The format for network logs. Defaults to :console.
  class Launcher
    # rubocop:disable Metrics/ParameterLists
    def initialize(url:, inputfile:, output:, cookies:, headers:, auth:, headless: true, port: 0, wait_window_loaded: false,
                   wait_network_idle: false, print_options: {}, remote_browser_url: nil, network_log_format: :console)
      @url = url
      @inputfile = inputfile
      @port = port
      @headless = headless
      @output = output
      @cookies = cookies
      @headers = headers
      @auth = auth
      @manager = nil
      @wait_window_loaded = wait_window_loaded
      @wait_network_idle = wait_network_idle
      @print_options = print_options || {}
      @remote_browser_url = remote_browser_url
      @custom_session = nil
      @network_log_format = network_log_format
    end

    # rubocop:enable Metrics/ParameterLists

    def launch
      runner = SessionRunner.new(
        session: session,
        url: @url,
        inputfile: @inputfile,
        output: @output,
        cookies: @cookies,
        headers: @headers,
        auth: @auth,
        wait_window_loaded: @wait_window_loaded,
        wait_network_idle: @wait_network_idle,
        print_options: @print_options,
        network_log_format: @network_log_format
      )
      runner.run
    end

    def stop
      @manager&.stop
      @custom_session&.close
    end

    private

    def session
      if @remote_browser_url
        @custom_session = Bidi::Session.new(session_url: @remote_browser_url, headless: @headless)
      else
        @manager = ChromedriverManager.new(port: @port, headless: @headless)
        @manager.start
        @manager.session
      end
    end
  end
end
