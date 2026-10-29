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
  # between them. nil turns the gate off. A forked child gets a semaphore of its own, so permits held by the parent's
  # threads at the fork cannot be lost in it.
  module SessionGate
    LOCK = Mutex.new

    class << self
      # Runs the block with a permit, released however the block ends. Waits for one at most
      # Bidi2pdf.session_start_timeout (default: Bidi2pdf.default_timeout) seconds, then raises
      # SessionStartTimeoutError - a queue behind a hung setup fails loudly instead of growing.
      def with_permit
        semaphore, limit = current
        return yield unless semaphore

        acquired, waited = acquire(semaphore)
        Bidi2pdf.notification_service.instrument("session_gate.bidi2pdf", { limit: limit, wait: waited, acquired: acquired })
        raise SessionStartTimeoutError.new(timeout_message(limit, waited), details: { limit: limit, waited: waited }) unless acquired

        begin
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

      # The semaphore for the configured limit in this process - a new one after a fork or a change of the limit
      # (whoever holds a permit of the old one still returns it there).
      def current
        limit = Bidi2pdf.session_start_concurrency
        return [nil, nil] if limit.nil?

        LOCK.synchronize do
          if @semaphore.nil? || @limit != limit || @pid != Process.pid
            @semaphore = Concurrent::Semaphore.new(limit)
            @limit = limit
            @pid = Process.pid
          end
          [@semaphore, @limit]
        end
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
