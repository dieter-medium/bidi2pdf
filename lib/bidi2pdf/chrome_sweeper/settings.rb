# frozen_string_literal: true

module Bidi2pdf
  class ChromeSweeper
    SCOPES = %i[recorded all].freeze
    DEFAULT_ORPHAN_AGE = 600
    DEFAULT_MIN_AGE = 60
    DEFAULT_UNRESPONSIVE_CHECKS = 2
    DEFAULT_PIDS_BUDGET = 0.8
    DEFAULT_THREADS_PER_SESSION = 110
    DEFAULT_LEASE_TTL = SessionRegistry::DEFAULT_LEASE_TTL

    # What a ChromeSweeper closes and when - validated on construction; an unknown setting raises
    # ArgumentError.
    #
    # @!attribute scope [Symbol] :recorded (sessions a SessionRegistry knows) or :all.
    # @!attribute orphan_age [Numeric, nil] close sessions older than this; nil turns the rule off.
    # @!attribute min_age [Numeric] never close a session younger than this.
    # @!attribute unresponsive_checks [Integer, nil] close after this many failed checks in a row.
    # @!attribute max_sessions [Integer, Symbol, nil] the limit; +:auto+ derives it from pids_limit.
    # @!attribute pids_limit [Integer, nil] the chromedriver container's pids limit, for +:auto+.
    # @!attribute pids_budget [Float] share of +pids_limit+ Chrome sessions may use.
    # @!attribute threads_per_session [Integer] threads (Docker counts them as pids) of one session.
    # @!attribute interval [Numeric, nil] seconds between sweeps of ChromeSweeper#start's thread.
    # @!attribute dry_run [Boolean] report what would be closed, close nothing.
    # @!attribute lease_ttl [Numeric] for registry entries without a TTL of their own (written by
    #   bidi2pdf 0.1.18): renewed within this many seconds means a live process holds it. Entries
    #   written since carry the TTL their owner's heartbeat promises (SessionRegistry#hold).
    Settings = Data.define(:scope, :orphan_age, :min_age, :unresponsive_checks, :max_sessions, :pids_limit,
                           :pids_budget, :threads_per_session, :interval, :dry_run, :lease_ttl) do
      # rubocop:disable-next Metrics/ParameterLists
      def initialize(scope: :recorded, orphan_age: DEFAULT_ORPHAN_AGE, min_age: DEFAULT_MIN_AGE,
                     unresponsive_checks: DEFAULT_UNRESPONSIVE_CHECKS, max_sessions: nil, pids_limit: nil,
                     pids_budget: DEFAULT_PIDS_BUDGET, threads_per_session: DEFAULT_THREADS_PER_SESSION,
                     interval: nil, dry_run: false, lease_ttl: DEFAULT_LEASE_TTL)
        super
        validate_scope!
        validate_numbers!
      end

      # The session limit in force: +max_sessions+, or for +:auto+ floor(pids_limit x pids_budget /
      # threads_per_session), at least 1 - nil (no limit) when +:auto+ has no pids_limit.
      def limit
        return max_sessions unless max_sessions == :auto
        return nil unless pids_limit

        [(pids_limit * pids_budget / threads_per_session).floor, 1].max
      end

      private

      def validate_scope!
        return if SCOPES.include?(scope)

        raise Bidi2pdf::InvalidConfigError, "chrome_sweeper: scope must be one of #{SCOPES.inspect}, got #{scope.inspect}"
      end

      def validate_numbers!
        to_h.slice(:orphan_age, :interval, :pids_limit).each { |name, value| positive!(name, value, allow_nil: true) }
        to_h.slice(:pids_budget, :threads_per_session, :lease_ttl).each { |name, value| positive!(name, value) }
        positive!(:min_age, min_age, allow_zero: true)
        count!(:unresponsive_checks, unresponsive_checks)
        count!(:max_sessions, max_sessions) unless max_sessions == :auto
      end

      def positive!(name, value, allow_nil: false, allow_zero: false)
        return if value.nil? && allow_nil
        return if value.is_a?(Numeric) && (value.positive? || (allow_zero && value.zero?))

        raise Bidi2pdf::InvalidConfigError, "chrome_sweeper: #{name} must be a positive number, got #{value.inspect}"
      end

      def count!(name, value)
        return if value.nil? || (value.is_a?(Integer) && value.positive?)

        raise Bidi2pdf::InvalidConfigError, "chrome_sweeper: #{name} must be nil or a positive Integer, got #{value.inspect}"
      end
    end
  end
end
