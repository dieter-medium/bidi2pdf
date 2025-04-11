# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    # rubocop: disable  Metrics/AbcSize
    class NetworkEventFormatter
      attr_reader :color_enabled

      # ANSI styles
      RESET = "\e[0m"
      BOLD = "\e[1m"
      DIM = "\e[2m"
      RED = "\e[31m"
      GREEN = "\e[32m"
      YELLOW = "\e[33m"
      CYAN = "\e[36m"
      GRAY = "\e[90m"

      def initialize(color: true)
        @color_enabled = color
      end

      def log(event)
        pretty_log(event).each_line { |line| Bidi2pdf.network_events_logger.info(line.chomp) }
      end

      def pretty_log(event)
        status = event.http_status_code ? "HTTP #{event.http_status_code}" : "pending"
        status_color = color_for_status(event.http_status_code)
        start = event.format_timestamp(event.start_timestamp)
        finish = event.end_timestamp ? event.format_timestamp(event.end_timestamp) : dim("...")
        duration = event.duration_seconds ? cyan("#{event.duration_seconds}s") : dim("in progress")
        timing_details = format_timing(event)
        bytes = event.bytes_received ? format_bytes(event.bytes_received) : dim("N/A")

        <<~LOG.strip
          #{bold("┌─ Network Event ──────────────────────────────────────")}
          #{bold("│ Request: ")}#{event.http_method || "?"} #{event.url}#{"          "}
          #{bold("│ State:   ")}#{event.state}
          #{bold("│ Status:  ")}#{status_color}#{status}#{reset}
          #{bold("│ Started: ")}#{start}
          #{bold("│ Ended:   ")}#{finish}
          #{bold("│ Duration:")} #{duration}
          #{bold("│ Received:")} #{bytes}
          #{timing_details}
          #{bold("└──────────────────────────────────────────────────────")}
        LOG
      end

      private

      def format_timing(event)
        return "" unless event.timing.is_a?(Hash)

        keys = %w[
          requestTime proxyStart proxyEnd dnsStart dnsEnd connectStart connectEnd
          sslStart sslEnd workerStart workerReady sendStart sendEnd receiveHeadersEnd
        ]

        visible = keys.map do |key|
          next unless event.timing[key]

          label = key.gsub(/([A-Z])/, ' \1').capitalize
          "#{dim("│")} #{label.ljust(20)}: #{event.timing[key].round(2)} ms#{reset}"
        end.compact

        return "" if visible.empty?

        [dim("│").to_s, dim("│ Timing Phases:").to_s].concat(visible).join("\n")
      end

      # === Color Helpers ===

      def color_for_status(code)
        return gray unless code

        case code.to_i
        when 200..299 then green
        when 300..499 then yellow
        when 500..599 then red
        else gray
        end
      end

      def bold(str) = color_enabled ? "#{BOLD}#{str}#{RESET}" : str

      def dim(str) = color_enabled ? "#{DIM}#{str}#{RESET}" : str

      def green(str = "") = color_enabled ? "#{GREEN}#{str}" : str

      def yellow(str = "") = color_enabled ? "#{YELLOW}#{str}" : str

      def red(str = "") = color_enabled ? "#{RED}#{str}" : str

      def cyan(str = "") = color_enabled ? "#{CYAN}#{str}" : str

      def gray(str = "") = color_enabled ? "#{GRAY}#{str}" : str

      def reset = color_enabled ? RESET : ""

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
    end

    # rubocop: enable  Metrics/AbcSize
  end
end
