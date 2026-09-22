# frozen_string_literal: true

require "time"

module Bidi2pdf
  # Builds the render manifest (--manifest FILE) from a completed Bidi2pdf::Result plus the
  # input/browser/header context around it. Redacts secret-
  # bearing headers and never records cookie values at all.
  class Manifest
    SCHEMA_VERSION = 1

    REDACT_HEADER_NAMES = %w[authorization proxy-authorization cookie set-cookie x-api-key api-key].freeze
    SENSITIVE_SUBSTRINGS = %w[token secret password authorization api-key apikey].freeze

    def initialize(result:, input:, headers: {}, navigation_duration_ms: nil, browser: {})
      @result = result
      @input = input
      @headers = headers
      @navigation_duration_ms = navigation_duration_ms
      @browser = browser
    end

    def self.redact(headers)
      headers.to_h { |key, value| [key, sensitive?(key) ? "[REDACTED]" : value] }
    end

    def self.sensitive?(key)
      normalized = key.to_s.downcase

      REDACT_HEADER_NAMES.include?(normalized) || SENSITIVE_SUBSTRINGS.any? { |substring| normalized.include?(substring) }
    end

    def to_h
      base = {
        schema_version: SCHEMA_VERSION,
        bidi2pdf_version: Bidi2pdf::VERSION,
        created_at: Time.now.utc.iso8601,
        input: @input,
        output: output_section,
        browser: @browser,
        navigation: navigation_section,
        render: { duration_ms: @result.duration_ms },
        console: @result.console,
        network_failures: @result.network_failures,
        warnings: @result.warnings
      }

      @headers.empty? ? base : base.merge(headers: self.class.redact(@headers))
    end

    def to_json(*)
      to_h.to_json(*)
    end

    private

    def output_section
      { path: @result.output, pages: @result.pages, bytes: @result.bytes, sha256: @result.sha256 }
    end

    def navigation_section
      (@result.navigation || {}).merge(duration_ms: @navigation_duration_ms)
    end
  end
end
