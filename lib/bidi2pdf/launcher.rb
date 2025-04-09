# frozen_string_literal: true

require_relative "chromedriver_manager"
require_relative "session_runner"
require_relative "bidi/session"

module Bidi2pdf
  class Launcher
    # rubocop:disable Metrics/ParameterLists
    def initialize(url:, output:, cookies:, headers:, auth:, headless: true, port: 0, wait_window_loaded: false,
                   wait_network_idle: false, print_options: {}, remote_browser_url: nil)
      @url = url
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
    end

    # rubocop:enable Metrics/ParameterLists

    def launch
      runner = SessionRunner.new(
        session: session,
        url: @url,
        output: @output,
        cookies: @cookies,
        headers: @headers,
        auth: @auth,
        wait_window_loaded: @wait_window_loaded,
        wait_network_idle: @wait_network_idle,
        print_options: @print_options
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
