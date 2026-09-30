# frozen_string_literal: true

module Bidi2pdf
  class CLI < Thor
    # Output of `bidi2pdf sessions` and `bidi2pdf sweep` (ChromeSweeper). Never prints a tab URL or
    # any page content - only ids, ages, tab counts and what was done.
    module SessionCommands
      # CLI flag => ChromeSweeper setting, for the ones that are only passed when given.
      SWEEP_FLAGS = { older_than: :orphan_age, max_sessions: :max_sessions, min_age: :min_age }.freeze

      private

      def chrome_sweeper
        url = options[:remote_browser_url]
        raise Thor::Error, "--remote-browser-url is required" if url.to_s.empty?

        Bidi2pdf::ChromeSweeper.new(url, scope: options[:scope].to_sym, dry_run: options[:dry_run], **sweep_flags)
      rescue Bidi2pdf::InvalidConfigError => e
        raise Thor::Error, e.message
      end

      # Thor hands every numeric over as a Float; the session limit is a count.
      def sweep_flags
        SWEEP_FLAGS.filter_map do |flag, setting|
          value = options[flag]
          [setting, setting == :max_sessions ? value.to_i : value] unless value.nil?
        end.to_h
      end

      def session_hash(info)
        { id: info.id, age: info.age&.round, source: info.source, tabs: info.tabs, responsive: info.responsive }
      end

      def print_sessions(infos)
        return puts "no sessions" if infos.empty?

        infos.each do |info|
          age = info.age ? "#{info.age.round}s" : "?"
          puts format("%-34<id>s %8<age>s  %-8<source>s %2<tabs>d tab(s)  %<state>s",
                      id: info.id, age: age, source: info.source, tabs: info.tabs,
                      state: info.responsive ? "responsive" : "unresponsive")
        end
      end

      def sweep_hash(result)
        { reason: result.reason, sessions: result.sessions, dry_run: result.dry_run, skipped: result.skipped,
          closed: result.closed.map(&:to_h), unresponsive: result.unresponsive, limit: result.limit,
          limit_exceeded: result.limit_exceeded, errors: result.errors }
      end

      def print_sweep(result)
        return puts "skipped: another sweep is running" if result.skipped

        verb = result.dry_run ? "would close" : "closed"
        result.closed.each { |closed| puts "#{verb} #{closed.id} (#{closed.why}, #{closed.age}s old)" }
        puts "#{verb} #{result.closed_count} of #{result.sessions} session(s)"
        print_sweep_problems(result)
      end

      def print_sweep_problems(result)
        puts "limit #{result.limit} still exceeded - no session old enough to close" if result.limit_exceeded
        result.errors.each { |error| warn "error: #{error}" }
      end
    end
  end
end
