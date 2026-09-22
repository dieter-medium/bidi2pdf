# frozen_string_literal: true

require "digest"
require "base64"

module Bidi2pdf
  # Builds a Bidi2pdf::Result by subscribing to the gem's own instrumentation events
  # (Bidi2pdf::Notifications) around a block that does the actual rendering, rather than changing
  # what Launcher/SessionRunner/BrowserTab return - Launcher#launch keeps returning the raw base64
  # PDF when no output file is given, exactly as the programmatic API already promises (see
  # spec/acceptance/launcher_spec.rb).
  class ResultCollector
    # #pdf_bytes is the raw, decoded PDF (nil if nothing was printed) - not part of Result#to_h
    # (which only carries bytesize/sha256/pages), but what a stdout-output render (--output -)
    # writes to $stdout, and what a caller can hand to Bidi2pdf::PdfInspection itself.
    #
    # #console/#network_failures are exposed live (not only via the Result #around eventually
    # returns) so a caller running inside the block - Recipe::Runner's assertions - can read them
    # before the block itself finishes.
    attr_reader :requested_url, :navigation_event, :pdf_bytes, :console

    def initialize(requested_url:, command:, output: nil)
      @requested_url = requested_url
      @command = command
      @output = output
      @console = []
      @network_events = {}
      @pdf_bytes = nil
    end

    # Runs the block with the collector subscribed, then returns a Bidi2pdf::Result - success with
    # whatever was captured, or failure describing whatever the block raised. Never itself raises.
    def around
      subscribe
      start = now_ms

      begin
        yield
        build_result(ok: true, duration_ms: elapsed_ms(start))
      rescue StandardError => e
        build_result(ok: false, duration_ms: elapsed_ms(start), error: e)
      end
    ensure
      unsubscribe
    end

    def network_failures
      @network_events.values
                     .select { |event| event.state == "error" || (event.http_status_code && event.http_status_code >= 400) }
                     .map { |event| { url: event.url, method: event.http_method, status: event.http_status_code, state: event.state } }
    end

    private

    def now_ms = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)

    def elapsed_ms(start) = (now_ms - start).round

    def subscribe
      handlers = {
        "navigate_to.bidi2pdf" => method(:on_navigate),
        "render_html_content.bidi2pdf" => method(:on_navigate),
        "browser_console_log_received.bidi2pdf" => method(:on_console),
        "network_event_received.bidi2pdf" => method(:on_network_event),
        "print.bidi2pdf" => method(:on_print)
      }

      # Capture the Proc #subscribe actually stored (it converts &handler into one), so
      # #unsubscribe below can remove exactly this registration - passing the handler positionally
      # rather than as a second &block, since Notifications#unsubscribe(pattern, block = nil)
      # clears *every* subscriber for that pattern when block is nil/omitted.
      @registered = handlers.map { |pattern, handler| [pattern, Bidi2pdf.notification_service.subscribe(pattern, &handler)] }
    end

    def unsubscribe
      Array(@registered).each { |pattern, block| Bidi2pdf.notification_service.unsubscribe(pattern, block) }
    end

    # Kept for its #duration (used by Manifest's navigation.duration_ms); Result itself doesn't
    # surface navigation timing separately from the overall duration_ms.
    def on_navigate(event)
      @navigation_event = event
    end

    def on_console(event)
      payload = event.payload
      @console << { level: payload[:level], text: payload[:text] }
    end

    def on_network_event(event)
      network_event = event.payload[:event]
      return unless network_event

      @network_events[network_event.id] = network_event
    end

    def on_print(event)
      pdf_base64 = event.payload[:pdf_base64]
      @pdf_bytes = pdf_base64 ? Base64.decode64(pdf_base64) : nil
    end

    # rubocop:disable-next Naming/MethodParameterName
    def build_result(ok:, duration_ms:, error: nil)
      Result.new(
        command: @command,
        ok: ok,
        output: @output,
        bytes: pdf_bytes&.bytesize,
        sha256: pdf_bytes ? Digest::SHA256.hexdigest(pdf_bytes) : nil,
        pages: PdfInspection.page_count(pdf_bytes),
        duration_ms: duration_ms,
        navigation: navigation_info,
        console: @console,
        network_failures: network_failures,
        warnings: warnings,
        error: ok ? nil : ErrorCodes.describe(error)
      )
    end

    def navigation_info
      final = final_navigation_event

      {
        requested_url: requested_url,
        final_url: final&.url || requested_url,
        status: final&.http_status_code
      }
    end

    # Best-effort external approximation of what BrowserTab#send(:correlated_navigation_response)
    # already computes internally (not exposed publicly): among the network events this collector
    # observed, the ones carrying a real BiDi "navigation" id are main-frame document requests: the
    # one with the latest start_timestamp among those sharing the most recent such navigation id is
    # the final hop of that navigation, and its own #url is therefore the page actually reached.
    def final_navigation_event
      candidates = @network_events.values.select { |event| event.navigation && event.http_status_code }
      return nil if candidates.empty?

      winning_navigation = candidates.max_by(&:start_timestamp).navigation
      candidates.select { |event| event.navigation == winning_navigation }.max_by(&:start_timestamp)
    end

    def warnings
      return [] unless pdf_bytes
      return [] if PdfInspection.available?

      ["pages requires the pdf-reader gem"]
    end
  end
end
