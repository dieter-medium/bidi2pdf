# frozen_string_literal: true

require "concurrent-ruby"
require "logger"

require_relative "bidi2pdf/process_tree"
require_relative "bidi2pdf/launcher"
require_relative "bidi2pdf/bidi/session"
require_relative "bidi2pdf/dsl"
require_relative "bidi2pdf/notifications"
require_relative "bidi2pdf/notifications/logging_subscriber"
require_relative "bidi2pdf/notifications/json_subscriber"
require_relative "bidi2pdf/session_warmer"
require_relative "bidi2pdf/verbose_logger"

module Bidi2pdf # rubocop:disable Metrics/ModuleLength
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

  # Base class for every error this gem raises. Carries the machine-readable surface used by
  # --json/--json-stream/manifests/recipe results (see Bidi2pdf::ErrorCodes): #retryable? and
  # #hint are overridden per subclass below where a useful default exists; #details is set at
  # raise time for structured, serializable context (e.g. which selector, which assertion).
  class Error < StandardError
    attr_reader :details

    def initialize(message = nil, details: {})
      @details = details
      super(message)
    end

    def retryable? = false

    def hint = nil
  end

  class SessionNotStartedError < Error
    def retryable? = true

    def hint = "Check Chrome/chromedriver are installed and reachable, or that --remote-browser-url points at a running instance"
  end

  class WebsocketError < Error
    def retryable? = true
  end

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

  class CmdTimeoutError < ClientError
    def retryable? = true

    def hint = "Raise --default-timeout"
  end

  class PrintError < Error; end

  class ScreenshotError < Error; end

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

  class NavigationAuthError < NavigationError
    attr_reader :url

    def initialize(url, message = nil)
      @url = url
      super("Navigation to #{url} failed due to authentication error. #{message}")
    end

    def hint = "Pass --auth user:pass, or check the credentials are still valid"
  end

  class NavigationTimeoutError < NavigationError
    def retryable? = true

    def hint = "Raise --default-timeout, or add --wait-network-idle if the page loads data after the load event"
  end

  class NavigationNotFoundError < NavigationError
    def hint = "Check the URL is correct"
  end

  class NavigationDNSError < NavigationError
    def retryable? = true

    def hint = "Check the hostname is correct and reachable from this machine/container"
  end

  # --- Errors introduced for the CLI/recipe surface.
  # Same style as the errors above: a thin subclass per failure mode, message text carried at the
  # raise site so it stays exactly as specific as the situation warrants.

  class MissingInputError < Error; end

  class MultipleInputSourcesError < Error; end

  class EmptyInputError < Error; end

  class InvalidConfigError < Error; end

  class InvalidPrintOptionError < Error; end

  class InvalidRecipeError < Error; end

  class SelectorNotFoundError < Error; end

  class PageNotAsExpectedError < Error; end

  class OutputWriteError < Error; end

  class PdfInspectionUnavailableError < Error
    def hint = "Install the pdf-reader gem, or drop assertions/fields that need it"
  end

  # Loaded here, after the error classes above, since these reference them at load time.
  require_relative "bidi2pdf/error_codes"
  require_relative "bidi2pdf/exit_codes"
  require_relative "bidi2pdf/result"
  require_relative "bidi2pdf/pdf_inspection"
  require_relative "bidi2pdf/result_collector"
  require_relative "bidi2pdf/manifest"
  require_relative "bidi2pdf/schema"
  require_relative "bidi2pdf/diagnose"
  require_relative "bidi2pdf/recipe"

  # Global configuration for Bidi2pdf

  class << self
    attr_accessor :default_timeout, :enable_default_logging_subscriber, :log_truncate_limit, :chromedriver_log_level
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

    # Truncates a value for safe log output - a raw url/param can be a `data:` URL whose base64
    # payload is proportional to document size, and logging it whole can be large enough to choke
    # CI log ingestion (confirmed live: GitHub Actions' log UI stalls badly on very long single
    # lines, reading as a hung job even though the process underneath is fine).
    #
    # @param [Object] value The value to truncate (converted via #to_s).
    # @param [Integer] limit The maximum number of bytes to keep. Defaults to
    #   +Bidi2pdf.log_truncate_limit+, itself configurable via +Bidi2pdf.configure+.
    # @return [String] The value unchanged if short enough, otherwise a truncated prefix plus a
    #   byte-count marker. Truncation is byte-based (not character-based), since the goal is
    #   bounding actual log-entry size; a partial trailing multi-byte character is scrubbed rather
    #   than left as invalid UTF-8.
    def truncate_for_log(value, limit: log_truncate_limit)
      str = value.to_s
      return str if str.bytesize <= limit

      truncated = str.byteslice(0, limit).scrub("")
      "#{truncated}... (#{str.bytesize} bytes total)"
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

    config.log_truncate_limit = 200

    config.notification_service = Notifications
  end
end
