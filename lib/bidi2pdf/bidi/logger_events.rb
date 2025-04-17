# frozen_string_literal: true

require_relative "network_event"
require_relative "browser_console_logger"

module Bidi2pdf
  module Bidi
    class LoggerEvents
      attr_reader :context_id, :browser_console_logger

      def initialize(context_id)
        @context_id = context_id
        @browser_console_logger = BrowserConsoleLogger.new(Bidi2pdf.browser_console_logger)
      end

      def handle_event(data)
        event = data["params"]
        method = data["method"]

        if event.dig("source", "context") == context_id
          handle_response(method, event)
        else
          # this should be Bidi2pdf.logger and not Bidi2pdf.browser_console_logger
          Bidi2pdf.logger.debug2 "Ignoring Log event: #{method}, context_id: #{context_id}, params: #{event}"
        end
      rescue StandardError => e
        # this should be Bidi2pdf.logger and not Bidi2pdf.browser_console_logger
        Bidi2pdf.logger.error "Error handling Log event: #{e.message}\n#{e.backtrace&.join("\n")}"
      end

      def handle_response(_method, event)
        level = resolve_log_level(event["level"])
        text = event["text"]
        args = event["args"] || []
        stack_trace = event["stackTrace"]
        timestamp = event["timestamp"]

        Bidi2pdf.notification_service.instrument("browser_console_log_received.bidi2pdf",
                                                 {
                                                   level: level,
                                                   text: text,
                                                   args: args,
                                                   stack_trace: stack_trace,
                                                   timestamp: timestamp
                                                 })

        browser_console_logger.builder
                              .with_level(level)
                              .with_timestamp(timestamp)
                              .with_text(text)
                              .with_args(args)
                              .with_stack_trace(stack_trace)
                              .log_event
      end

      def resolve_log_level(js_level)
        case js_level
        when "info", "warn", "error", "trace"
          js_level.to_sym
        else
          :debug
        end
      end
    end
  end
end
