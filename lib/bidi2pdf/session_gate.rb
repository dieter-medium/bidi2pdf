# frozen_string_literal: true

require "concurrent"

module Bidi2pdf
  # At most Bidi2pdf.session_start_concurrency Chrome session setups at once in this process - from the session
  # request to the first open tab (README "Session start limit"). When several new sessions are set up at the same
  # moment, chromedriver/Chrome sometimes leaves a setup command unanswered and the session hangs until the command
  # times out (measured on chromedriver/Chrome 156: three setups at once failed, two did not). Rendering is never
  # limited, only the setup before it.
  #
  # The limit holds per process: processes sharing one Chrome (Puma workers, a job process) divide its budget
  # between them. It is one budget for the process, whichever Chrome a setup goes to - two independent chromedrivers
  # still take turns (an endpoint-scoped gate would not; not built). nil turns the gate off.
  #
  # The limit is read once per process - at its first setup, and again in a forked child, whose semaphore is its own
  # so permits held by the parent's threads at the fork cannot be lost in it. A later change takes effect after a
  # restart and is logged: set it at boot (an initializer), not while setups run. Changing it live would have to
  # keep the setups in flight counted, which needs an API Concurrent::Semaphore does not document.
  #
  # Bidi2pdf.session_gate replaces the semaphore with an object of your own, to share the budget across processes
  # (a file lock, a database or Redis lock). Its contract: +with_permit+ runs the block only while it holds a permit,
  # gives the permit back however the block ends, raises Bidi2pdf::SessionStartTimeoutError when none comes free in
  # time, and loses no permit when a process dies or forks. Every setup path still comes through here, so the
  # notification below is sent either way - it trusts that the block runs under a permit. session_start_concurrency
  # and session_start_timeout then apply only if that object reads them.
  module SessionGate
    LOCK = Mutex.new

    class << self
      # Runs the block with a permit, released however the block ends. Waits for one at most
      # Bidi2pdf.session_start_timeout (default: Bidi2pdf.default_timeout) seconds, then raises
      # SessionStartTimeoutError - a queue behind a hung setup fails loudly instead of growing.
      def with_permit(&)
        return with_custom_gate(Bidi2pdf.session_gate, &) if Bidi2pdf.session_gate

        semaphore, limit = current
        return yield unless semaphore

        acquired, waited = acquire(semaphore)
        refuse(limit, waited) unless acquired

        # Everything after the permit is taken sits inside the ensure - a raising subscriber must not keep it.
        begin
          Bidi2pdf.notification_service.instrument("session_gate.bidi2pdf", { limit: limit, wait: waited, acquired: true })
          yield
        ensure
          semaphore.release(1)
        end
      end

      # Forgets the semaphore; the next permit builds one for the configured limit. For specs.
      def reset!
        LOCK.synchronize { @semaphore = @limit = @pid = @warned_limit = nil }
      end

      private

      # The wait is the time until the custom gate runs the block - it reports a timeout itself, by raising.
      def with_custom_gate(gate)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        gate.with_permit do
          waited = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3)
          Bidi2pdf.notification_service.instrument("session_gate.bidi2pdf", { limit: nil, wait: waited, acquired: true, gate: gate.class.name })
          yield
        end
      end

      # The semaphore of this process, built for the limit configured at its first setup (and in a forked child).
      def current
        LOCK.synchronize do
          if @pid == Process.pid
            warn_changed_limit
          else
            @limit = Bidi2pdf.session_start_concurrency
            @semaphore = @limit && Concurrent::Semaphore.new(@limit)
            @pid = Process.pid
          end
          [@semaphore, @limit]
        end
      end

      # Once per new value: the limit in force stays until a restart.
      def warn_changed_limit
        configured = Bidi2pdf.session_start_concurrency
        return if [@limit, @warned_limit].include?(configured)

        @warned_limit = configured
        Bidi2pdf.logger.warn "session_gate: session_start_concurrency changed to #{configured.inspect} after the first session " \
                             "setup - #{@limit.inspect} stays in force until the process restarts"
      end

      def refuse(limit, waited)
        Bidi2pdf.notification_service.instrument("session_gate.bidi2pdf", { limit: limit, wait: waited, acquired: false })
        raise SessionStartTimeoutError.new(timeout_message(limit, waited), details: { limit: limit, waited: waited })
      end

      def acquire(semaphore)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        acquired = semaphore.try_acquire(1, Bidi2pdf.session_start_timeout || Bidi2pdf.default_timeout)
        [acquired, (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3)]
      end

      def timeout_message(limit, waited)
        "No Chrome session could start within #{waited}s: #{limit} other session setup(s) in this process held every permit"
      end
    end
  end
end
