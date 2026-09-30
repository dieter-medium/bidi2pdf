# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module Commands
      # goog:cdp.sendCommand - chromedriver's BiDi extension that runs one Chrome DevTools Protocol
      # command; without a +session+ it runs at browser level (e.g. SystemInfo.getProcessInfo).
      class CdpSendCommand
        include Base

        def initialize(method:, params: {}, session: nil)
          @cdp_method = method
          @cdp_params = params
          @session = session
        end

        def params = { method: @cdp_method, params: @cdp_params, session: @session }.compact

        def method_name
          "goog:cdp.sendCommand"
        end
      end
    end
  end
end
