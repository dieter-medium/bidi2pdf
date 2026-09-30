# frozen_string_literal: true

module Bidi2pdf
  class SessionRegistry
    # Keeps the leases of every session this process holds fresh: one thread per process renews
    # them in their registry files every +interval+ seconds, so a sweeper in another process (a
    # second Puma worker, a job worker sharing the registry directory) can tell a live session
    # from one whose process died. The thread runs only while something is held.
    #
    # Fork-aware: a child process (Puma forks its workers) starts with nothing held and without the
    # parent's thread - the parent's sessions are the parent's to renew.
    module Heartbeat
      DEFAULT_INTERVAL = DEFAULT_LEASE_TTL / 3.0

      @mutex = Mutex.new

      class << self
        # @return [Numeric] seconds between renewals - keep it well below the sweeper's lease_ttl.
        attr_writer :interval

        def interval = @interval || DEFAULT_INTERVAL

        def hold(registry, session_id)
          synchronize do
            (held[registry.path] ||= [registry, Set.new])[1] << session_id.to_s
            @thread = Thread.new { beat_loop } unless @thread&.alive?
          end
        end

        def release(registry, session_id)
          synchronize do
            ids = held.dig(registry.path, 1)
            next unless ids

            ids.delete(session_id.to_s)
            held.delete(registry.path) if ids.empty?
          end
        end

        # @return [Array<String>] the session ids this process holds in +registry+'s file.
        def held_ids(registry)
          synchronize { held.dig(registry.path, 1).to_a }
        end

        # Renews every held lease now.
        def beat!(now: Time.now.to_i)
          synchronize { held.values.map { |registry, ids| [registry, ids.to_a] } }
            .each { |registry, ids| registry.renew(ids, at: now) }
        end

        private

        def beat_loop
          loop do
            sleep interval
            break if synchronize { held.empty? }

            beat!
          end
        rescue StandardError => e
          Bidi2pdf.logger.warn "session registry heartbeat stopped: #{e.message}"
        end

        def held
          reset_after_fork
          @held ||= {}
        end

        def reset_after_fork
          return if @pid == Process.pid

          @pid = Process.pid
          @held = {}
          @thread = nil
        end

        def synchronize(&)
          @mutex.synchronize(&)
        end
      end
    end
  end
end
