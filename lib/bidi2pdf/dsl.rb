# frozen_string_literal: true

require "bidi2pdf"

module Bidi2pdf
  module DSL
    # Provides a DSL for managing browser sessions and tabs
    # using the Bidi2pdf library. This module includes a method to create and manage
    # browser tabs within a controlled session.

    # rubocop: disable  Metrics/AbcSize
    #
    # Executes a block of code within the context of a browser tab.
    #
    # This method handles the setup and teardown of a browser session, user context,
    # browser window, and tab. It ensures that resources are properly cleaned up
    # after the block is executed.
    #
    # @param [String, nil] remote_browser_url The URL of a remote browser to connect to.
    #   If provided, the session will connect to this browser in headless mode.
    # @param [Integer] port The port to use for the local browser session. Defaults to 0 (chooses a random port).
    # @param [Boolean] headless Whether to run the browser in headless mode. Defaults to true.
    # @param [Array<String>] chrome_args Additional arguments to pass to the Chrome browser.
    #   Defaults to the `DEFAULT_CHROME_ARGS` from the `Bidi2pdf::Bidi::Session` class.
    #
    # @yield [tab] The browser tab created within the session.
    # @yieldparam [Object] tab The browser tab object.
    #
    # @example Using a local browser session
    #   Bidi2pdf::DSL.with_tab(port: 9222, headless: false) do |tab|
    #     # Perform actions with the tab
    #   end
    #
    # @example Using a remote browser session
    #   Bidi2pdf::DSL.with_tab(remote_browser_url: "http://remote-browser:9222/session") do |tab|
    #     # Perform actions with the tab
    #   end
    #
    # @return [void]
    def self.with_tab(remote_browser_url: nil, port: 0, headless: true, chrome_args: Bidi2pdf::Bidi::Session::DEFAULT_CHROME_ARGS.dup)
      manager = nil
      session = nil
      tab = nil

      begin
        session = if remote_browser_url
                    Bidi2pdf::Bidi::Session.new(
                      session_url: remote_browser_url,
                      headless: true, # remote is always headless
                      chrome_args: chrome_args
                    )
                  else
                    manager = Bidi2pdf::ChromedriverManager.new(port: port, headless: headless)
                    manager.start
                    manager.session
                  end

        session.start
        session.client.on_close { Bidi2pdf.logger.info "WebSocket session closed" }

        browser = session.browser
        context = browser.create_user_context
        window = context.create_browser_window
        tab = window.create_browser_tab

        yield(tab)
      ensure
        tab&.close
        window&.close
        context&.close
        session&.close
        manager&.stop
      end
    end

    # rubocop: enable  Metrics/AbcSize
  end
end
