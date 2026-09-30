# frozen_string_literal: true

require "digest"
require "json"
require "socket"
require "tmpdir"

module Bidi2pdf
  # Remembers which sessions bidi2pdf opened on a shared (remote) chromedriver, when, by which
  # process, and whether that process is still alive - in a small JSON file per chromedriver URL - so
  # a process started later, or a ChromeSweeper, can find and close the ones a process that died
  # without a clean shutdown left behind (see SessionSweeper). chromedriver itself keeps a session
  # until someone deletes it, and it drops any tag we could attach to one (a custom capability is
  # accepted but echoed nowhere - checked against chromedriver 153), hence a file.
  #
  # Liveness is a lease: a session the process #hold s is renewed by its Heartbeat every
  # Heartbeat.interval seconds, and every entry carries its own TTL - the time the owner promises to
  # renew it within (three heartbeats) - so a sweeper in another process never has to guess how
  # often that owner renews. A session whose lease is fresh belongs to a live process - a render in
  # flight or a warm spare - and no sweeper closes it; one whose lease ran out belongs to a dead
  # process. #record alone writes an entry nobody renews.
  #
  # Everything here is best effort and fail-open: a directory that is not writable, a locked-out or
  # corrupt file only switches orphan tracking off for this process (one warning, one
  # +session_warmer.registry_unavailable.bidi2pdf+ notification) - rendering never depends on it.
  # The file is created 0600 and every change happens under an exclusive lock, so processes sharing
  # the directory (Puma workers, a job worker, a spec run) can record at the same time.
  class SessionRegistry
    FILE_PREFIX = "bidi2pdf-sessions-"
    # Seconds a lease stays fresh without a renewal when its entry carries no TTL of its own (written
    # by bidi2pdf 0.1.18) - matches that version's fixed 20 s heartbeat.
    DEFAULT_LEASE_TTL = 60

    attr_reader :path

    def self.owner = "#{Socket.gethostname}:#{Process.pid}"

    def initialize(session_url, dir: nil)
      @path = File.join(dir || Dir.tmpdir, "#{FILE_PREFIX}#{Digest::SHA256.hexdigest(session_url.to_s)[0, 16]}.json")
      @warned = false
    end

    # Records a session the caller opened and keeps its lease fresh while this process lives.
    def hold(session_id)
      return false if session_id.nil?

      recorded = record(session_id, ttl: Heartbeat.lease_ttl)
      Heartbeat.hold(self, session_id)
      recorded
    end

    # Stops renewing the lease but keeps the entry - for a session this process could not close, so
    # a sweeper takes it once the lease ran out.
    def release(session_id)
      Heartbeat.release(self, session_id) unless session_id.nil?
    end

    # Writes an entry, leased from +created_at+ on for +ttl+ seconds (nil: the reader's default) but
    # not renewed (see #hold).
    # Times are stored as fractions of a second: a whole-second timestamp could cost a short lease
    # (0.5 s heartbeats: 1.5 s) up to a second of its life. Entries of whole seconds still read.
    def record(session_id, created_at: Time.now.to_f, ttl: nil)
      return false if session_id.nil?

      update do |entries|
        entries[session_id.to_s] = { "created_at" => created_at.to_f, "renewed_at" => created_at.to_f, "ttl" => ttl, "owner" => self.class.owner }.compact
      end
    end

    # Forgets a session the caller closed itself (or found gone).
    def forget(session_id)
      return false if session_id.nil?

      release(session_id)
      update { |entries| entries.delete(session_id.to_s) }
    end

    # Renews the leases of +session_ids+ that are still recorded, for +ttl+ seconds when given.
    def renew(session_ids, at: Time.now.to_f, ttl: nil)
      update do |entries|
        session_ids.select { |id| entries.key?(id) }.each do |id|
          entries[id]["renewed_at"] = at.to_f
          entries[id]["ttl"] = ttl if ttl
        end
      end
    end

    # Every recorded session: { id => opened at (epoch seconds) }.
    def recorded
      read.transform_values { |entry| entry["created_at"] }
    end

    # The recorded session ids whose lease is still fresh at +now+ - sessions of a live process. An
    # entry's own TTL wins; +ttl+ is only for entries without one.
    def leased(now: Time.now.to_f, ttl: DEFAULT_LEASE_TTL)
      read.select { |_, entry| entry["renewed_at"].to_f + (entry["ttl"] || ttl) >= now }.keys
    end

    # The recorded session ids opened at or before +cutoff+ (epoch seconds).
    def recorded_before(cutoff)
      recorded.select { |_, created_at| created_at <= cutoff }.keys
    end

    private

    def read
      return {} unless File.exist?(path)

      File.open(path, File::RDONLY) do |file|
        file.flock(File::LOCK_SH)
        parse(file.read)
      end
    rescue SystemCallError, IOError => e
      unavailable!(e)
      {}
    end

    def update
      File.open(path, File::RDWR | File::CREAT, 0o600) do |file|
        file.flock(File::LOCK_EX)
        entries = parse(file.read)
        yield entries
        file.rewind
        file.truncate(0)
        file.write(JSON.generate(entries))
        file.flush
      end
      true
    rescue SystemCallError, IOError => e
      unavailable!(e)
      false
    end

    # A corrupt or foreign file counts as empty rather than as an error; an entry of the first
    # format (just the creation time) has no lease.
    def parse(text)
      data = text.to_s.empty? ? {} : JSON.parse(text)
      return {} unless data.is_a?(Hash)

      data.filter_map { |id, entry| [id, normalize(entry)] if id.is_a?(String) && normalize(entry) }.to_h
    rescue JSON::ParserError
      {}
    end

    def normalize(entry)
      return { "created_at" => entry } if entry.is_a?(Numeric)

      entry if entry.is_a?(Hash) && entry["created_at"].is_a?(Numeric)
    end

    def unavailable!(error)
      return if @warned

      @warned = true
      Bidi2pdf.logger.warn "session_warmer: session registry #{path} unavailable, leftover sessions will not be tracked: #{error.message}"
      Bidi2pdf.notification_service.instrument("session_warmer.registry_unavailable.bidi2pdf", { path: path, error: error.class.name })
    end
  end
end

require_relative "session_registry/heartbeat"
