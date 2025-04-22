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
  PAPER_FORMATS_CM = {
    letter: { width: 21.59, height: 27.94 },
    legal: { width: 21.59, height: 35.56 },
    tabloid: { width: 27.94, height: 43.18 },
    ledger: { width: 43.18, height: 27.94 },
    a0: { width: 84.1, height: 118.9 },
    a1: { width: 59.4, height: 84.1 },
    a2: { width: 42.0, height: 59.4 },
    a3: { width: 29.7, height: 42.0 },
    a4: { width: 21.0, height: 29.7 },
    a5: { width: 14.8, height: 21.0 },
    a6: { width: 10.5, height: 14.8 }
  }.freeze

  class Error < StandardError; end

  class SessionNotStartedError < Error; end

  class WebsocketError < Error; end

  class ClientError < WebsocketError; end

  class CmdError < ClientError
    attr_reader :cmd, :response

    def initialize(cmd, response)
      @cmd = cmd
      @response = response

      super("Error response: #{response["error"]} #{cmd.inspect}")
    end
  end

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

  class NavigationError < Error; end

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

    def translate_paper_format(format)
      format = format.to_s.downcase.to_sym

      dim = PAPER_FORMATS_CM[format]

      raise ArgumentError, "Invalid paper format: #{format}" unless dim

      width = dim[:width] || 0
      height = dim[:height] || 0

      { width: width, height: height }
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
