# frozen_string_literal: true

module Bidi2pdf
  class CLI < Thor
    # Shared machinery for --json/--json-stream/--output - across render/diagnose/run: reserving
    # stdout for exactly one machine-readable payload, and mapping a Result to a process exit
    # status.
    module JsonOutput
      private

      # Bidi2pdf.logger (and friends) default to $stdout (see lib/bidi2pdf.rb), so a
      # --json/--output - render has to redirect them for its duration or every log line would
      # land in the same stream as the JSON document / PDF bytes it is trying to keep pure.
      # Logger#reopen swaps the destination in place, so nothing else holding a reference to
      # these loggers needs to know.
      def reserve_stdout_for_machine_output
        loggers = [Bidi2pdf.logger, Bidi2pdf.network_events_logger, Bidi2pdf.browser_console_logger].compact
        loggers.each { |logger| logger.logger.reopen($stderr) }

        yield
      ensure
        loggers.each { |logger| logger.logger.reopen($stdout) }
      end

      def exit_for_result(result)
        exit(result.ok? ? Bidi2pdf::ExitCodes::SUCCESS : Bidi2pdf::ExitCodes.for(result.error[:code]))
      end
    end
  end
end
