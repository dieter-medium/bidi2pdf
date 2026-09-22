# frozen_string_literal: true

module Bidi2pdf
  # Maps an ErrorCodes string to the process exit status the CLI reports. Centralized here so
  # render/diagnose/run share one table instead of each re-deciding what a given failure is worth.
  module ExitCodes
    SUCCESS = 0
    CLI_ERROR = 2
    BROWSER_ERROR = 3
    PAGE_NOT_AS_EXPECTED = 4
    OUTPUT_ERROR = 6
    INTERNAL_ERROR = 70

    CODE_TO_EXIT = {
      "MISSING_INPUT" => CLI_ERROR,
      "MULTIPLE_INPUT_SOURCES" => CLI_ERROR,
      "EMPTY_INPUT" => CLI_ERROR,
      "INVALID_CONFIG" => CLI_ERROR,
      "INVALID_PRINT_OPTION" => CLI_ERROR,
      "INVALID_RECIPE" => CLI_ERROR,
      "PDF_INSPECTION_UNAVAILABLE" => CLI_ERROR,
      "BROWSER_LAUNCH_FAILED" => BROWSER_ERROR,
      "BROWSER_DISCONNECTED" => BROWSER_ERROR,
      "COMMAND_TIMEOUT" => BROWSER_ERROR,
      "NAVIGATION_FAILED" => BROWSER_ERROR,
      "NAVIGATION_TIMEOUT" => BROWSER_ERROR,
      "NAVIGATION_AUTH" => BROWSER_ERROR,
      "NAVIGATION_NOT_FOUND" => BROWSER_ERROR,
      "DNS_ERROR" => BROWSER_ERROR,
      "SELECTOR_NOT_FOUND" => PAGE_NOT_AS_EXPECTED,
      "PAGE_NOT_AS_EXPECTED" => PAGE_NOT_AS_EXPECTED,
      "SCRIPT_ERROR" => PAGE_NOT_AS_EXPECTED,
      "STYLE_ERROR" => PAGE_NOT_AS_EXPECTED,
      "PDF_GENERATION_FAILED" => OUTPUT_ERROR,
      "SCREENSHOT_FAILED" => OUTPUT_ERROR,
      "OUTPUT_WRITE_FAILED" => OUTPUT_ERROR,
      "INTERNAL_ERROR" => INTERNAL_ERROR
    }.freeze

    def self.for(code)
      CODE_TO_EXIT.fetch(code, INTERNAL_ERROR)
    end
  end
end
