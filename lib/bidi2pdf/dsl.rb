# frozen_string_literal: true

require "bidi2pdf"

module Bidi2pdf
  module DSL
    # rubocop: disable  Metrics/AbcSize
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
        session&.close
        manager&.stop
      end
    end

    # rubocop: enable  Metrics/AbcSize
  end
end
