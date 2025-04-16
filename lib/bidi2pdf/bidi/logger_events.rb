# frozen_string_literal: true

require_relative "network_event"
require_relative "js_logger_helper"

module Bidi2pdf
  module Bidi
    class LoggerEvents
      include JsLoggerHelper

      attr_reader :context_id

      def initialize(context_id)
        @context_id = context_id
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
        timestamp = format_timestamp(event["timestamp"])
        prefix = log_prefix(timestamp)

        log_message(level, prefix, text)
        log_args(prefix, args)
        log_stack_trace(prefix, stack_trace) if stack_trace && level == :error
      end

      private

      def log_message(level, prefix, text)
        return unless text

        Bidi2pdf.browser_console_logger.send(level, "#{prefix} #{text}")
      end

      def log_args(prefix, args)
        return if args.empty?

        Bidi2pdf.browser_console_logger.debug("#{prefix} Args: #{args.inspect}")
      end

      def log_stack_trace(prefix, trace)
        formatted_trace = format_stack_trace(trace)
        Bidi2pdf.browser_console_logger.error("#{prefix} Stack trace captured:\n#{formatted_trace}")
      end

      def format_timestamp(timestamp)
        return "N/A" unless timestamp

        Time.at(timestamp.to_f / 1000).utc.strftime("%Y-%m-%d %H:%M:%S.%L UTC")
      end

      def resolve_log_level(js_level)
        case js_level
        when "info", "warn", "error", "trace"
          js_level.to_sym
        else
          :debug
        end
      end

      def log_prefix(timestamp)
        "[#{timestamp}][Browser Console Log]"
      end
    end
  end
end
