# frozen_string_literal: true

require "digest"
require "json"
require "tmpdir"

module Bidi2pdf
  # Remembers which sessions a SessionWarmer opened on a shared (remote) chromedriver, and when, in a
  # small JSON file per chromedriver URL - so a process started later can find and close the ones a
  # process that died without a clean shutdown left behind (see SessionSweeper). chromedriver itself
  # keeps a session until someone deletes it, and it drops any tag we could attach to one (a custom
  # capability is accepted but echoed nowhere - checked against chromedriver 153), hence a file.
  #
  # Everything here is best effort and fail-open: a directory that is not writable, a locked-out or
  # corrupt file only switches orphan tracking off for this process (one warning, one
  # +session_warmer.registry_unavailable.bidi2pdf+ notification) - rendering never depends on it.
  # The file is created 0600 and every change happens under an exclusive lock, so processes sharing
  # the directory (a dev server, a job worker, a spec run) can record at the same time.
  class SessionRegistry
    FILE_PREFIX = "bidi2pdf-sessions-"

    attr_reader :path

    def initialize(session_url, dir: nil)
      @path = File.join(dir || Dir.tmpdir, "#{FILE_PREFIX}#{Digest::SHA256.hexdigest(session_url.to_s)[0, 16]}.json")
      @warned = false
    end

    # Records a session the caller just opened.
    def record(session_id, created_at: Time.now.to_i)
      return false if session_id.nil?

      update { |entries| entries[session_id.to_s] = created_at.to_i }
    end

    # Forgets a session the caller closed itself (or found gone).
    def forget(session_id)
      return false if session_id.nil?

      update { |entries| entries.delete(session_id.to_s) }
    end

    # Every recorded session: { id => opened at (epoch seconds) }.
    def recorded
      read
    end

    # The recorded session ids opened at or before +cutoff+ (epoch seconds).
    def recorded_before(cutoff)
      entries = read
      entries.select { |_, created_at| created_at <= cutoff }.keys
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

    # A corrupt or foreign file counts as empty rather than as an error.
    def parse(text)
      data = text.to_s.empty? ? {} : JSON.parse(text)
      return {} unless data.is_a?(Hash)

      data.select { |id, created_at| id.is_a?(String) && created_at.is_a?(Integer) }
    rescue JSON::ParserError
      {}
    end

    def unavailable!(error)
      return if @warned

      @warned = true
      Bidi2pdf.logger.warn "session_warmer: session registry #{path} unavailable, leftover sessions will not be tracked: #{error.message}"
      Bidi2pdf.notification_service.instrument("session_warmer.registry_unavailable.bidi2pdf", { path: path, error: error.class.name })
    end
  end
end
