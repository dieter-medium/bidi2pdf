# frozen_string_literal: true

require "net/http"
require "uri"

module Bidi2pdf
  # Closes sessions a SessionWarmer recorded (SessionRegistry) on a shared chromedriver that are
  # older than a cutoff - left behind by a process that died without a clean shutdown, and holding a
  # whole Chrome each until someone deletes them. Run once when a warmer starts.
  #
  # Only recorded sessions are ever touched - another tool's sessions on the same chromedriver never
  # are, and neither is one whose lease a live process keeps renewing (SessionRegistry#hold). A
  # recorded session that is already gone ("invalid session id" / 404) is just forgotten.
  # Fail-open: any error is logged and ends the sweep; it never raises.
  class SessionSweeper
    # @param session_url [String] the chromedriver's new-session URL (".../session").
    # @param registry [SessionRegistry]
    # @param http [#call, nil] (method, url) -> status code; injectable for tests.
    def initialize(session_url, registry, http: nil)
      @session_url = session_url.to_s.chomp("/")
      @registry = registry
      @http = http || method(:net_http)
    end

    # Closes recorded sessions opened more than +older_than+ seconds before +now+.
    #
    # @return [Integer] how many sessions were actually closed.
    def sweep(older_than:, now: Time.now.to_i)
      leftovers = @registry.recorded_before(now - older_than) - @registry.leased(now: now)
      closed = leftovers.count { |id| closed_now?(id) }
      report(closed)
      closed
    rescue StandardError => e
      Bidi2pdf.logger.warn "session_warmer: sweeping leftover sessions failed: #{e.message}"
      Bidi2pdf.notification_service.instrument("session_warmer.sweep_failed.bidi2pdf", { error: e.class.name })
      0
    end

    private

    # True when this call closed the session; a session already gone is forgotten but not counted.
    def closed_now?(id)
      status = @http.call(:delete, "#{@session_url}/#{id}")
      return false unless [200, 404].include?(status)

      @registry.forget(id)
      status == 200
    end

    def report(closed)
      return if closed.zero?

      Bidi2pdf.logger.info "session_warmer: closed #{closed} leftover session(s) on #{@session_url}"
      Bidi2pdf.notification_service.instrument("session_warmer.orphans_closed.bidi2pdf", { count: closed })
    end

    # chromedriver answers a DELETE of a session it no longer has with 404 "invalid session id".
    def net_http(method, url)
      uri = URI(url)
      request = method == :delete ? Net::HTTP::Delete.new(uri) : Net::HTTP::Get.new(uri)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 30) do |http|
        http.request(request).code.to_i
      end
    end
  end
end
