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
  # still take turns (an endpoint-scoped gate would not; not built). nil turns the gate off. Changing the limit
  # resizes the one semaphore, so setups in flight keep counting: a lower limit lets new setups wait until enough of
  # them are done. A forked child gets a semaphore of its own, so permits held by the parent's threads at the fork
  # cannot be lost in it.
  #
  # Bidi2pdf.session_gate replaces the semaphore with an object of your own - one that answers +with_permit+ with a
  # block - to share the budget across processes (a file lock, a database or Redis lock). Every setup path still
  # comes through here, so the notification below is sent either way; session_start_concurrency and
  # session_start_timeout then apply only if that object reads them.
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
        LOCK.synchronize { @semaphore = @limit = @pid = nil }
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

      # The semaphore for the configured limit in this process: built on first use and after a fork, resized when
      # the limit changes.
      def current
        limit = Bidi2pdf.session_start_concurrency

        LOCK.synchronize do
          if @pid != Process.pid
            @semaphore = limit && Concurrent::Semaphore.new(limit)
            @pid = Process.pid
          elsif @limit != limit
            resize(limit)
          end
          @limit = limit
          [@semaphore, @limit]
        end
      end

      # Keeps the permits in flight counted: free permits may go below zero, so a lower limit makes new setups wait
      # until enough holders are done. From nil, only setups that start afterwards count.
      def resize(limit)
        if limit.nil? || @semaphore.nil?
          @semaphore = limit && Concurrent::Semaphore.new(limit)
        elsif limit > @limit
          @semaphore.release(limit - @limit)
        else
          @semaphore.reduce_permits(@limit - limit)
        end
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
