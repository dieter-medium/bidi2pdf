# frozen_string_literal: true

require "forwardable"
require_relative "chromedriver_api"
require_relative "session_registry"
require_relative "chrome_sweeper/settings"
require_relative "chrome_sweeper/inspector"

module Bidi2pdf
  # Closes Chrome sessions a shared chromedriver holds that nobody will close any more - left behind
  # by a process that died, or stuck in a tab that never returns - and keeps the number of sessions
  # below a limit. chromedriver keeps every session (a whole Chrome) until someone deletes it.
  #
  # Which sessions it looks at (+scope+):
  # - +:recorded+ (default) - only sessions a SessionRegistry proves were opened through bidi2pdf.
  # - +:all+ - every session on that chromedriver (+GET /sessions+), aged by its first tab. Only for
  #   a chromedriver the application owns: on a shared one it closes other clients' old sessions.
  #
  # What it closes, in this order - never a session of +own_sessions+ and never one younger than
  # +min_age+, not even over the limit, so a render in flight is never killed:
  # 1. sessions older than +orphan_age+;
  # 2. sessions that failed +unresponsive_checks+ checks in a row (no answer, or a renderer burning
  #    CPU at full speed between two sweeps - an endless loop);
  # 3. while more sessions exist than +max_sessions+, the oldest remaining ones. When that is not
  #    enough, the sweep reports +limit_exceeded+ and closes nothing more.
  #
  # Run it once (#sweep!, ChromeSweeper.sweep!) - e.g. when the application suspects a leak - or
  # periodically (+interval+, #start/#stop). One sweep at a time, across processes too (a lock file
  # next to the registry). Fail-open: a sweep never raises; errors land in the Result. See Settings
  # for every setting and its default.
  #
  # @example A periodic sweeper for an application's own chromedriver
  #   sweeper = Bidi2pdf::ChromeSweeper.new("http://remote-chrome:3000/session", scope: :all,
  #                                         max_sessions: :auto, pids_limit: 1024, interval: 60)
  #   sweeper.start
  class ChromeSweeper
    extend Forwardable

    # One closed (or, in a dry run, would-be closed) session. +why+: :orphan, :unresponsive or
    # :over_limit.
    Closed = Data.define(:id, :age, :why)

    # What one sweep saw and did.
    Result = Data.define(:reason, :sessions, :inspected, :closed, :unresponsive, :limit, :limit_exceeded,
                         :dry_run, :skipped, :errors, :duration) do
      def closed_count = closed.size
    end

    # A renderer that used at least this share of the wall-clock time between two sweeps counts as
    # stuck in a loop.
    BUSY_CPU_SHARE = 0.9

    # The bookkeeping of one sweep.
    Sweep = Struct.new(:total, :closed, :unresponsive, :errors, :limit_exceeded) do
      def initialize(total = 0) = super(total, [], [], [], false)

      def remaining = total - closed.size
    end

    attr_reader :session_url, :settings, :registry

    def_delegators :@settings, :scope, :orphan_age, :min_age, :unresponsive_checks, :interval, :dry_run, :limit

    # One-shot sweep with a throw-away sweeper. Give it a +check_interval+ for the unresponsive rule
    # to apply - see #sweep!.
    #
    # @return [Result]
    def self.sweep!(session_url, reason: :manual, check_interval: nil, **)
      new(session_url, **).sweep!(reason: reason, check_interval: check_interval)
    end

    # @param session_url [String] chromedriver's new-session URL (".../session").
    # @param registry [SessionRegistry, nil] defaults to the one for +session_url+ in +registry_dir+.
    # @param own_sessions [#call] returns the ids of the caller's live sessions - never touched.
    # @param api [ChromedriverApi, nil], inspector [Inspector, nil], clock [#call] - for tests.
    # @param settings see Settings.
    # @raise [InvalidConfigError] for a setting out of range.
    def initialize(session_url, registry: nil, registry_dir: nil, own_sessions: -> { [] },
                   api: nil, inspector: nil, clock: -> { Time.now.to_f }, **settings)
      @session_url = session_url.to_s
      @settings = Settings.new(**settings)
      @own_sessions = own_sessions
      @clock = clock
      @registry = registry || Bidi2pdf::SessionRegistry.new(@session_url, dir: registry_dir)
      @api = api || Bidi2pdf::ChromedriverApi.new(@session_url)
      @inspector = inspector || Inspector.new(clock: clock)
      @mutex = Mutex.new
      @wakeup = Thread::Queue.new
      @failures = Hash.new(0)
      @first_seen = {}
      @cpu_samples = {}
    end

    # Every session in scope, inspected (age, tabs, responsive) - for diagnostics; closes nothing.
    #
    # @return [Array<Inspector::SessionInfo>]
    def sessions
      recorded = @registry.recorded
      in_scope(@api.sessions, recorded).map { |entry| @inspector.examine(entry, recorded_at: recorded[entry.id]) }
    end

    # Inspects every session in scope and counts its checks, like a sweep, but closes nothing.
    #
    # @return [Array<Inspector::SessionInfo>]
    def observe
      @mutex.synchronize { observe_entries(@api.sessions) }
    end

    # Sweeps once. Skipped (Result#skipped) when another sweep - in this or another process - is
    # still running.
    #
    # A session counts as hung only after +unresponsive_checks+ failed checks, one per sweep - a
    # one-shot sweep never gets there. With +check_interval+ it first checks
    # +unresponsive_checks - 1+ times, +check_interval+ seconds apart (#observe), so a single call
    # applies every rule. The periodic thread doesn't need that: its sweeps are the checks.
    #
    # @param reason [Symbol] why - reported in the notification (:manual, :periodic, :create_failed…).
    # @param check_interval [Numeric, nil] seconds between those checks; nil sweeps right away.
    # @return [Result]
    def sweep!(reason: :manual, check_interval: nil)
      check_first(check_interval) if check_interval
      started = monotonic
      return result(reason, started, skipped: true) unless @mutex.try_lock

      begin
        with_lock_file { |locked| locked ? run(reason, started) : result(reason, started, skipped: true) }
      ensure
        @mutex.unlock
      end
    end

    # Starts the periodic sweep thread (needs an +interval+). Idempotent.
    def start
      raise Bidi2pdf::InvalidConfigError, "chrome_sweeper: start needs an interval" unless interval

      @thread ||= Thread.new { sweep!(reason: :periodic) until @wakeup.pop(timeout: interval) == :stop }
      self
    end

    # Stops the periodic sweep thread and waits for a sweep in progress to finish.
    def stop
      return unless @thread

      @wakeup << :stop
      @thread.join
      @thread = nil
    end

    private

    def run(reason, started)
      sweep, infos = sweep_sessions
      report(result(reason, started, sweep: sweep, inspected: infos))
    rescue StandardError => e
      Bidi2pdf.logger.warn "chrome_sweeper: sweep of #{@session_url} failed: #{e.message}"
      Bidi2pdf.notification_service.instrument("chrome_sweeper.failed.bidi2pdf", { reason: reason, error: e.class.name })
      result(reason, started, sweep: Sweep.new.tap { |failed| failed.errors << e.message })
    end

    # A config error raises; a failed check only means the sweep has fewer checks to go on.
    def check_first(check_interval)
      raise Bidi2pdf::InvalidConfigError, "chrome_sweeper: check_interval must be a positive number, got #{check_interval.inspect}" unless check_interval.is_a?(Numeric) && check_interval.positive?

      (unresponsive_checks.to_i - 1).times { observe_then_wait(check_interval) }
    end

    def observe_then_wait(check_interval)
      observe
    rescue StandardError => e
      Bidi2pdf.logger.warn "chrome_sweeper: checking #{@session_url} before the sweep failed: #{e.message}"
    ensure
      sleep check_interval
    end

    def sweep_sessions
      entries = @api.sessions
      infos = observe_entries(entries)
      sweep = Sweep.new(entries.size)
      decide(infos.select { |info| info.age >= min_age }, sweep)
      [sweep, infos]
    end

    # In-scope sessions not owned by the caller and not known to be younger than min_age, with the
    # registry time when there is one. A young recorded session is not even attached to.
    def candidates(entries)
      recorded = @registry.recorded
      own = Array(@own_sessions.call).map(&:to_s)
      in_scope(entries, recorded).filter_map do |entry|
        recorded_at = recorded[entry.id]
        next if own.include?(entry.id) || (recorded_at && now - recorded_at < min_age)

        [entry, recorded_at]
      end
    end

    def in_scope(entries, recorded)
      scope == :all ? entries : entries.select { |entry| recorded.key?(entry.id) }
    end

    def observe_entries(entries)
      forget_gone(entries)
      candidates(entries).map { |entry, recorded_at| track(@inspector.examine(entry, recorded_at: recorded_at)) }
    end

    # Sessions chromedriver no longer has are dropped from the registry and from this sweeper's own
    # tracking - most sessions end normally, so a long-running sweeper would otherwise keep every id
    # it ever saw.
    def forget_gone(entries)
      ids = entries.map(&:id)
      (@registry.recorded.keys - ids).each { |id| @registry.forget(id) }
      (@first_seen.keys - ids).each { |id| forget_tracking(id) }
    end

    def forget_tracking(id)
      [@failures, @first_seen, @cpu_samples].each { |tracked| tracked.delete(id) }
    end

    # Counts failed checks per session across sweeps, and ages a session by when this sweeper first
    # saw it when nothing better is known.
    def track(info)
      count_check(info)
      @first_seen[info.id] ||= now
      info.with(age: [info.age || 0, now - @first_seen[info.id]].max)
    end

    def count_check(info)
      failed = !info.responsive || busy?(info)
      @failures[info.id] = failed ? @failures[info.id] + 1 : 0
      @cpu_samples[info.id] = [now, info.cpu_times]
    end

    def busy?(info)
      sampled_at, times = @cpu_samples[info.id]
      return false unless sampled_at && now > sampled_at

      info.cpu_times.any? { |pid, cpu| times.key?(pid) && (cpu - times[pid]) / (now - sampled_at) >= BUSY_CPU_SHARE }
    end

    def decide(eligible, sweep)
      eligible.each do |info|
        why = close_reason(info, sweep)
        close_session(info, why, sweep) if why
      end

      enforce_limit(eligible, sweep)
    end

    def close_reason(info, sweep)
      failed = @failures[info.id]
      note_unresponsive(info, failed, sweep) if unresponsive_checks && failed.positive?
      return :orphan if orphan_age && info.age > orphan_age

      :unresponsive if unresponsive_checks && failed >= unresponsive_checks
    end

    def note_unresponsive(info, failed, sweep)
      sweep.unresponsive << info.id
      Bidi2pdf.notification_service.instrument("chrome_sweeper.unresponsive.bidi2pdf", { id: info.id, checks: failed })
    end

    def enforce_limit(eligible, sweep)
      return unless over_limit?(sweep)

      oldest_open(eligible, sweep).each do |info|
        break unless over_limit?(sweep)

        close_session(info, :over_limit, sweep)
      end
      limit_exceeded(sweep) if over_limit?(sweep)
    end

    def over_limit?(sweep) = !limit.nil? && sweep.remaining > limit

    def oldest_open(eligible, sweep)
      closed_ids = sweep.closed.map(&:id)
      eligible.reject { |info| closed_ids.include?(info.id) }.sort_by { |info| -info.age }
    end

    def limit_exceeded(sweep)
      sweep.limit_exceeded = true
      Bidi2pdf.logger.warn "chrome_sweeper: #{sweep.remaining} sessions on #{@session_url}, limit #{limit} - none left old enough to close"
      Bidi2pdf.notification_service.instrument("chrome_sweeper.limit_exceeded.bidi2pdf", { sessions: sweep.remaining, limit: limit })
    end

    # Adds the session to the sweep's closed list unless chromedriver refused to close it.
    def close_session(info, why, sweep)
      return sweep.errors << "closing #{info.id} failed" unless dry_run || gone_after_delete?(info.id)

      sweep.closed << announce(Closed.new(id: info.id, age: info.age.round, why: why))
    end

    def announce(closed)
      Bidi2pdf.notification_service.instrument("chrome_sweeper.closed.bidi2pdf", closed.to_h.merge(dry_run: dry_run))
      closed
    end

    def gone_after_delete?(id)
      return false if @api.delete_session(id) == :failed

      @registry.forget(id)
      forget_tracking(id)
      true
    end

    def report(result)
      verb = dry_run ? "would close" : "closed"
      Bidi2pdf.logger.info "chrome_sweeper: #{verb} #{result.closed_count} of #{result.sessions} session(s) on #{@session_url}" if result.closed.any?
      Bidi2pdf.notification_service.instrument("chrome_sweeper.sweep.bidi2pdf", sweep_payload(result))
      result
    end

    def sweep_payload(result)
      result.to_h.slice(:reason, :sessions, :limit, :limit_exceeded, :dry_run, :duration)
            .merge(inspected: result.inspected.size, closed: result.closed_count)
    end

    def result(reason, started, sweep: Sweep.new, inspected: [], skipped: false)
      Result.new(reason: reason, sessions: sweep.total, inspected: inspected, closed: sweep.closed,
                 unresponsive: sweep.unresponsive, limit: limit, limit_exceeded: sweep.limit_exceeded,
                 dry_run: dry_run, skipped: skipped, errors: sweep.errors, duration: monotonic - started)
    end

    # A lock file next to the registry, so processes sharing it never sweep at the same time. When
    # the file cannot be created at all the sweep still runs (fail-open, like the registry itself).
    def with_lock_file
      file = open_lock_file
      return yield(true) unless file

      begin
        yield file.flock(File::LOCK_EX | File::LOCK_NB)
      ensure
        file.close
      end
    end

    def open_lock_file
      File.open("#{@registry.path}.lock", File::RDWR | File::CREAT, 0o600)
    rescue SystemCallError
      nil
    end

    def now = @clock.call

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
