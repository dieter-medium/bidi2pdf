# frozen_string_literal: true

require "json"

module Bidi2pdf
  # Structured result of a CLI command (render/diagnose/run) - the shape behind --json output, a
  # render manifest, and the final "result" event of --json-stream. Construct via .success/
  # .failure rather than .new directly so every Result is unambiguously one or the other.
  class Result
    SCHEMA_VERSION = 1

    attr_reader :command, :output, :bytes, :sha256, :pages, :duration_ms, :navigation,
                :console, :network_failures, :warnings, :error, :metadata

    # rubocop:disable-next Metrics/ParameterLists, Naming/MethodParameterName
    def initialize(command:, ok:, output: nil, bytes: nil, sha256: nil, pages: nil, duration_ms: nil,
                   navigation: nil, console: [], network_failures: [], warnings: [], error: nil, metadata: {})
      @command = command
      @ok = ok
      @output = output
      @bytes = bytes
      @sha256 = sha256
      @pages = pages
      @duration_ms = duration_ms
      @navigation = navigation
      @console = console
      @network_failures = network_failures
      @warnings = warnings
      @error = error
      @metadata = metadata
    end

    def self.success(**)
      new(ok: true, **)
    end

    def self.failure(error:, **)
      new(ok: false, error: error, **)
    end

    def ok? = @ok

    def to_h
      base = {
        schema_version: SCHEMA_VERSION,
        ok: ok?,
        command: command,
        output: output,
        bytes: bytes,
        sha256: sha256,
        pages: pages,
        duration_ms: duration_ms,
        navigation: navigation,
        console: console,
        network_failures: network_failures,
        warnings: warnings,
        error: error
      }

      metadata.empty? ? base : base.merge(metadata: metadata)
    end

    def to_json(*)
      to_h.to_json(*)
    end
  end
end
