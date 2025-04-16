# frozen_string_literal: true

require_relative "bidi2pdf/process_tree"
require_relative "bidi2pdf/launcher"
require_relative "bidi2pdf/bidi/session"
require_relative "bidi2pdf/dsl"
require_relative "bidi2pdf/notifications"
require_relative "bidi2pdf/notifications/logging_subscriber"
require_relative "bidi2pdf/verbose_logger"

require "logger"

module Bidi2pdf
  class Error < StandardError; end

  class SessionNotStartedError < Error; end

  class WebsocketError < Error; end

  class ClientError < WebsocketError; end

  class CmdError < ClientError; end

  class CmdResponseNotStoredError < ClientError; end

  class CmdTimeoutError < ClientError; end

  class PrintError < Error; end

  class ScriptInjectionError < Error; end

  class StyleInjectionError < Error; end

  class NotificationsError < Error
    attr_reader :causes

    def initialize(causes)
      @causes = causes
      exception_class_names = causes.map { |e| e.class.name }
      super("Notifications errors: #{exception_class_names.join(", ")}")
    end
  end

  @default_timeout = 60

  @notification_service = Notifications

  class << self
    attr_accessor :default_timeout, :notification_service
    attr_reader :logging_subscriber, :logger, :network_events_logger, :browser_console_logger

    # Allow configuration through a block
    def configure
      yield self if block_given?

      init
    end

    # rubocop:disable Naming/MemoizedInstanceVariableName
    def init
      @logging_subscriber ||= Notifications::LoggingSubscriber.new(logger: logger)
    end

    # rubocop:enable Naming/MemoizedInstanceVariableName

    def logger=(new_logger)
      @logger = Bidi2pdf::VerboseLogger.new new_logger
    end

    def network_events_logger=(new_network_events_logger)
      @network_events_logger = Bidi2pdf::VerboseLogger.new(new_network_events_logger)
    end

    def browser_console_logger=(new_browser_console_logger)
      @browser_console_logger = Bidi2pdf::VerboseLogger.new(new_browser_console_logger)
    end

    def logging_subscriber=(new_logging_subscriber)
      @logging_subscriber&.unsubscribe
      @logging_subscriber = new_logging_subscriber
    end
  end

  self.logger = Logger.new($stdout)
  logger.level = Logger::INFO

  self.network_events_logger = Logger.new($stdout)
  network_events_logger.level = Logger::FATAL

  self.browser_console_logger = Logger.new($stdout)
  browser_console_logger.level = Logger::WARN
end
