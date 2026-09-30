# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Bidi2pdf
  # The two chromedriver HTTP endpoints session cleanup needs, next to the BiDi protocol: the
  # non-standard +GET /sessions+ (every session on that chromedriver - WebDriver itself has no way to
  # list them, BiDi neither) and +DELETE /session/{id}+ (ends a session and its Chrome even when that
  # Chrome no longer answers BiDi).
  #
  # Built from the new-session URL every other part of bidi2pdf is configured with
  # ("http://host:3000/session").
  class ChromedriverApi
    # One entry of +GET /sessions+: chromedriver gives no creation time, no owner, and no hint
    # whether a client is still connected (checked against chromedriver 153/154).
    Entry = Data.define(:id, :websocket_url, :process_id)

    DEFAULT_TIMEOUT = 30

    attr_reader :session_url

    # @param session_url [String] chromedriver's new-session URL (".../session").
    # @param http [#call, nil] (method, url) -> [status, body]; injectable for tests.
    def initialize(session_url, http: nil, timeout: DEFAULT_TIMEOUT)
      @session_url = session_url.to_s.chomp("/")
      @timeout = timeout
      @http = http || method(:net_http)
    end

    # @return [Array<Entry>] every session chromedriver holds right now.
    def sessions
      status, body = @http.call(:get, sessions_url)
      raise Bidi2pdf::Error, "chromedriver answered #{status} to GET /sessions" unless status == 200

      Array(JSON.parse(body)["value"]).map do |session|
        capabilities = session["capabilities"] || {}
        Entry.new(id: session["id"], websocket_url: capabilities["webSocketUrl"], process_id: capabilities["goog:processID"])
      end
    end

    # Ends a session. chromedriver answers 404 ("invalid session id") for one it no longer has.
    #
    # @return [Symbol] :closed, :gone or :failed
    def delete_session(id)
      status, = @http.call(:delete, "#{session_url}/#{id}")
      case status
      when 200 then :closed
      when 404 then :gone
      else :failed
      end
    end

    private

    # "http://host:3000/session" -> "http://host:3000/sessions"; a chromedriver started with a
    # --url-base keeps its prefix.
    def sessions_url
      "#{session_url.delete_suffix("/session")}/sessions"
    end

    def net_http(method, url)
      uri = URI(url)
      request = method == :delete ? Net::HTTP::Delete.new(uri) : Net::HTTP::Get.new(uri)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: @timeout) do |http|
        response = http.request(request)
        [response.code.to_i, response.body]
      end
    end
  end
end
