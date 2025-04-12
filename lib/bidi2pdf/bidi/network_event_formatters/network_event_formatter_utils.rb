# frozen_string_literal: true

require "cgi"

module Bidi2pdf
  module Bidi
    module NetworkEventFormatters
      module NetworkEventFormatterUtils
        def format_bytes(size)
          return "N/A" unless size.is_a?(Numeric)

          units = %w[B KB MB GB TB]
          idx = 0
          while size >= 1024 && idx < units.size - 1
            size /= 1024.0
            idx += 1
          end
          format("%<size>.2f %<unit>s", size: size, unit: units[idx])
        end

        def parse_timing(event)
          return [] unless event.timing.is_a?(Hash)

          keys = %w[
          requestTime proxyStart proxyEnd dnsStart dnsEnd connectStart connectEnd
          sslStart sslEnd workerStart workerReady sendStart sendEnd receiveHeadersEnd
        ]

          keys.filter_map do |key|
            next unless event.timing[key]

            label = key.gsub(/([A-Z])/, ' \1').capitalize
            { label: label, key: key, ms: event.timing[key].round(2) }
          end
        end

        def format_timestamp(timestamp)
          return "N/A" unless timestamp

          Time.at(timestamp.to_f / 1000).utc.strftime("%Y-%m-%d %H:%M:%S.%L UTC")
        end

        def shorten_url(url)
          sanitized_url = CGI.escapeHTML(url)

          return sanitized_url unless sanitized_url.start_with?("data:text/html")

          "data:text/html,..."
        end
      end
    end
  end
end
