# frozen_string_literal: true

module Bidi2pdf
  # Maps an exception to the stable, machine-readable code used by --json/--json-stream/manifests
  # and recipe results. Derived from the existing Bidi2pdf::Error hierarchy rather than duplicated
  # beside it: a new failure mode gets a new subclass in lib/bidi2pdf.rb and a row here, never a
  # bare string minted ad hoc.
  #
  # MAPPING is ordered most-specific-subclass first - #for walks it in order and returns the first
  # match, so a subclass must appear before any of its ancestors.
  module ErrorCodes
    MAPPING = {
      MissingInputError => "MISSING_INPUT",
      MultipleInputSourcesError => "MULTIPLE_INPUT_SOURCES",
      EmptyInputError => "EMPTY_INPUT",
      InvalidConfigError => "INVALID_CONFIG",
      InvalidPrintOptionError => "INVALID_PRINT_OPTION",
      InvalidRecipeError => "INVALID_RECIPE",
      PdfInspectionUnavailableError => "PDF_INSPECTION_UNAVAILABLE",
      SessionNotStartedError => "BROWSER_LAUNCH_FAILED",
      CmdTimeoutError => "COMMAND_TIMEOUT",
      WebsocketError => "BROWSER_DISCONNECTED",
      NavigationTimeoutError => "NAVIGATION_TIMEOUT",
      NavigationAuthError => "NAVIGATION_AUTH",
      NavigationNotFoundError => "NAVIGATION_NOT_FOUND",
      NavigationDNSError => "DNS_ERROR",
      NavigationError => "NAVIGATION_FAILED",
      SelectorNotFoundError => "SELECTOR_NOT_FOUND",
      PageNotAsExpectedError => "PAGE_NOT_AS_EXPECTED",
      ScriptInjectionError => "SCRIPT_ERROR",
      StyleInjectionError => "STYLE_ERROR",
      PrintError => "PDF_GENERATION_FAILED",
      ScreenshotError => "SCREENSHOT_FAILED",
      OutputWriteError => "OUTPUT_WRITE_FAILED",
      Error => "INTERNAL_ERROR"
    }.freeze

    DEFAULT_CODE = "INTERNAL_ERROR"

    def self.for(exception)
      _klass, code = MAPPING.find { |klass, _code| exception.is_a?(klass) }

      code || DEFAULT_CODE
    end

    # Builds the {code:, message:, retryable:, hint:, details:} hash used as Result#error and in
    # recipe action/assertion failures. Works for any StandardError, not only a Bidi2pdf::Error -
    # an unexpected exception still gets INTERNAL_ERROR with retryable/hint defaulted safely.
    def self.describe(exception, details: {})
      {
        code: self.for(exception),
        message: exception.message,
        retryable: exception.respond_to?(:retryable?) ? exception.retryable? : false,
        hint: exception.respond_to?(:hint) ? exception.hint : nil,
        details: exception.respond_to?(:details) && !exception.details.empty? ? exception.details : details
      }
    end
  end
end
