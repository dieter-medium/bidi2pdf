# frozen_string_literal: true

require_relative "chromedriver_manager"
require_relative "session_runner"
require_relative "bidi/session"

module Bidi2pdf
  class Launcher
    def initialize(url:, output:, cookies:, headers:, auth:, headless: true, port: 0, wait_window_loaded: false,
                   wait_network_idle: false, print_options: {})
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
    end

    def launch
      @manager = ChromedriverManager.new(port: @port, headless: @headless)
      @manager.start

      runner = SessionRunner.new(
        session: @manager.session,
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
      @manager.stop
    end
  end
end
