# frozen_string_literal: true

require_relative "js_logger_helper"

module Bidi2pdf
  module Bidi
    class BrowserConsoleLoggerSuggar
      attr_reader :browser_console_logger

      def initialize(browser_console_logger)
        @browser_console_logger = browser_console_logger
      end

      def with_level(level)
        @level = level
        self
      end

      def with_prefix(prefix)
        @prefix = prefix
        self
      end

      def with_timestamp(timestamp)
        @timestamp = timestamp
        self
      end

      def with_text(text)
        @text = text
        self
      end

      def with_args(args)
        @args = args
        self
      end

      def with_stack_trace(stack_trace)
        @stack_trace = stack_trace
        self
      end

      def log_event
        browser_console_logger.log_message(@level, @prefix, @text)
        browser_console_logger.log_args(@prefix, @args)
        browser_console_logger.log_stack_trace(@prefix, @stack_trace) if @stack_trace && @level == :error
      end

      def prefix
        @prefix ||= "[#{BrowserConsoleLogger.format_timestamp(@timestamp)}][Browser Console Log]"
      end
    end

    class BrowserConsoleLogger
      include JsLoggerHelper

      attr_accessor :logger

      def initialize(logger)
        @logger = logger
      end

      def builder
        BrowserConsoleLoggerSuggar.new(self)
      end

      def log_message(level, prefix, text)
        return unless text

        logger.send(level, "#{prefix} #{text}")
      end

      def log_args(prefix, args)
        return if args.empty?

        logger.debug("#{prefix} Args: #{args.inspect}")
      end

      def log_stack_trace(prefix, trace)
        formatted_trace = format_stack_trace(trace)
        logger.error("#{prefix} Stack trace captured:\n#{formatted_trace}")
      end

      def self.format_timestamp(timestamp)
        return "N/A" unless timestamp

        Time.at(timestamp.to_f / 1000).utc.strftime("%Y-%m-%d %H:%M:%S.%L UTC")
      end
    end
  end
end
