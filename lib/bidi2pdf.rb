# frozen_string_literal: true

require_relative "bidi2pdf/process_tree"
require_relative "bidi2pdf/launcher"
require_relative "bidi2pdf/bidi/session"
require_relative "bidi2pdf/dsl"
require_relative "bidi2pdf/notifications"
require_relative "bidi2pdf/logging_subscriber"

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

  @logger = Logger.new($stdout)
  @logger.level = Logger::INFO

  @network_events_logger = Logger.new($stdout)
  @network_events_logger.level = Logger::FATAL

  @browser_console_logger = Logger.new($stdout)
  @browser_console_logger.level = Logger::WARN

  @default_timeout = 60

  @notification_service = Notifications

  class << self
    attr_accessor :logger, :default_timeout, :network_events_logger, :browser_console_logger, :notification_service

    # Allow configuration through a block
    def configure
      yield self if block_given?
    end
  end
end
