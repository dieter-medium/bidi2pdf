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

  class << self
    attr_accessor :default_timeout, :enable_default_logging_subscriber
    attr_reader :logging_subscriber, :logger, :network_events_logger, :browser_console_logger, :notification_service

    # Allow configuration through a block
    def configure
      yield self if block_given?

      init
    end

    def init
      self.logging_subscriber = (Notifications::LoggingSubscriber.new(logger: logger) if enable_default_logging_subscriber)
      begin
        require "websocket-native"

        logger.debug "websocket-native available; use enhance performance."
      rescue LoadError => e
        raise unless e.message =~ /websocket-native/

        logger.warn "websocket-native not available; installing it may enhance performance."
      end
    end

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

    def notification_service=(new_notification_service)
      @logging_subscriber&.unsubscribe

      @notification_service = new_notification_service
    end
  end

  configure do |config|
    config.logger = Logger.new($stdout)
    config.logger.level = Logger::INFO

    config.network_events_logger = Logger.new($stdout)
    config.network_events_logger.level = Logger::FATAL

    config.browser_console_logger = Logger.new($stdout)
    config.browser_console_logger.level = Logger::WARN

    config.enable_default_logging_subscriber = true

    config.default_timeout = 60

    config.notification_service = Notifications
  end
end
