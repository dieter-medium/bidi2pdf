# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module NetworkEventFormatters
      require_relative "network_event_formatters/network_event_formatter_utils"
      require_relative "network_event_formatters/network_event_console_formatter"
      require_relative "network_event_formatters/network_event_html_formatter"
    end
  end
end
