# frozen_string_literal: true

require "json"

module Bidi2pdf
  module Notifications
    # Emits one JSON object per line to an IO (stderr for --json-stream, docs/specs/llm-friendly-
    # spec.md section 7) as a render progresses, by subscribing to the same Bidi2pdf::Notifications
    # events Bidi2pdf::ResultCollector and LoggingSubscriber already use - no new instrumentation
    # points needed. #emit_result writes the final "result" event once the caller has a Result.
    class JsonSubscriber
      SCHEMA_VERSION = 1

      def initialize(io: $stderr)
        @io = io
        @start = now_ms
        subscribe
      end

      def emit_result(result)
        write(event: "result", result: result.to_h)
      end

      def unsubscribe
        Array(@registered).each { |pattern, block| Bidi2pdf.notification_service.unsubscribe(pattern, block) }
      end

      private

      def now_ms = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)

      def elapsed_ms = (now_ms - @start).round

      def subscribe
        handlers = {
          "navigate_to.bidi2pdf" => method(:on_navigate),
          "render_html_content.bidi2pdf" => method(:on_navigate),
          "page_loaded.bidi2pdf" => method(:on_page_loaded),
          "network_idle.bidi2pdf" => method(:on_network_idle),
          "browser_console_log_received.bidi2pdf" => method(:on_console),
          "print.bidi2pdf" => method(:on_print),
          "screenshot.bidi2pdf" => method(:on_screenshot)
        }

        @registered = handlers.map { |pattern, handler| [pattern, Bidi2pdf.notification_service.subscribe(pattern, &handler)] }
      end

      def on_navigate(event)
        write(event: "navigate", url: event.payload[:url])
      end

      def on_page_loaded(_event)
        write(event: "page_loaded")
      end

      def on_network_idle(_event)
        write(event: "network_idle")
      end

      def on_console(event)
        payload = event.payload
        write(event: "console", level: payload[:level], text: payload[:text])
      end

      def on_print(_event)
        write(event: "print")
      end

      def on_screenshot(_event)
        write(event: "screenshot")
      end

      def write(fields)
        @io.puts({ schema_version: SCHEMA_VERSION, t_ms: elapsed_ms }.merge(fields).to_json)
      end
    end
  end
end
