# frozen_string_literal: true

module Bidi2pdf
  class ChromeSweeper
    # Looks at one session on a chromedriver from the outside: attaches a second BiDi connection to
    # its +webSocketUrl+ (chromedriver allows that for any session), asks for the tab tree, the first
    # tab's +performance.timeOrigin+ (Chrome keeps no session start time anywhere - the first tab is
    # created with the session, so its time origin is the session's age to within a few hundred ms)
    # and the renderer CPU times (CDP +SystemInfo.getProcessInfo+ through +goog:cdp.sendCommand+).
    #
    # Read-only, and never reads page content: tab URLs are counted, not returned or logged (a
    # +data:+ URL carries the whole rendered document). Closes its own connection every time.
    class Inspector
      # @!attribute age [Float, nil] seconds since the session started, nil when nothing tells.
      # @!attribute source [Symbol] :registry, :tab or :unknown - where +age+ comes from.
      # @!attribute responsive [Boolean] whether the session answered the checks.
      # @!attribute cpu_times [Hash{Integer => Float}] renderer pid => CPU seconds.
      SessionInfo = Data.define(:id, :age, :source, :tabs, :responsive, :cpu_times)

      DEFAULT_TIMEOUT = 5

      # @param clock [#call] epoch seconds as a Float.
      # @param client_factory [#call] ws_url -> a started, open Bidi::Client; injectable for tests.
      def initialize(timeout: DEFAULT_TIMEOUT, clock: -> { Time.now.to_f }, client_factory: nil)
        @timeout = timeout
        @clock = clock
        @client_factory = client_factory || method(:connect)
      end

      # @param entry [ChromedriverApi::Entry]
      # @param recorded_at [Numeric, nil] epoch seconds the registry has for it; wins over the tab.
      # @return [SessionInfo]
      def examine(entry, recorded_at: nil)
        return unreachable(entry, recorded_at) if entry.websocket_url.nil?

        client = @client_factory.call(entry.websocket_url)
        probe(client, entry, recorded_at)
      rescue StandardError => e
        Bidi2pdf.logger.debug "chrome_sweeper: inspecting session #{entry.id} failed: #{e.message}"
        unreachable(entry, recorded_at)
      ensure
        client&.close
      end

      private

      def probe(client, entry, recorded_at)
        contexts = tree(client)
        return unreachable(entry, recorded_at) if contexts.nil?

        origin = contexts.empty? ? nil : time_origin(client, contexts.first["context"])
        age, source = age_of(recorded_at, origin)

        SessionInfo.new(id: entry.id, age: age, source: source, tabs: contexts.size,
                        responsive: contexts.empty? || !origin.nil?, cpu_times: cpu_times(client))
      end

      def tree(client)
        once_more_on_timeout { command(client, Bidi2pdf::Bidi::Commands::BrowsingContextGetTree.new).dig("result", "contexts") || [] }
      rescue Bidi2pdf::CmdTimeoutError
        nil
      end

      # A tab stuck in an endless loop never evaluates anything - nil then.
      def time_origin(client, context)
        evaluate = Bidi2pdf::Bidi::Commands::ScriptEvaluate.new(expression: "performance.timeOrigin", context: context, await_promise: false)
        value = once_more_on_timeout { command(client, evaluate) }.dig("result", "result", "value")
        value.is_a?(Numeric) ? value / 1000.0 : nil
      rescue Bidi2pdf::CmdError, Bidi2pdf::CmdTimeoutError
        nil
      end

      # On a freshly attached connection the first command to a session - and, seen once in the
      # acceptance run, to a tab - can time out although the session is healthy (chromedriver
      # 153/154); the second one answers. Only a second timeout counts.
      def once_more_on_timeout
        yield
      rescue Bidi2pdf::CmdTimeoutError
        yield
      end

      def cpu_times(client)
        processes = command(client, Bidi2pdf::Bidi::Commands::CdpSendCommand.new(method: "SystemInfo.getProcessInfo"))
                    .dig("result", "result", "processInfo") || []
        processes.select { |process| process["type"] == "renderer" }.to_h { |process| [process["id"], process["cpuTime"].to_f] }
      rescue Bidi2pdf::CmdError, Bidi2pdf::CmdTimeoutError
        {}
      end

      def age_of(recorded_at, origin)
        return [@clock.call - recorded_at, :registry] if recorded_at
        return [@clock.call - origin, :tab] if origin

        [nil, :unknown]
      end

      def unreachable(entry, recorded_at)
        age, source = age_of(recorded_at, nil)
        SessionInfo.new(id: entry.id, age: age, source: source, tabs: 0, responsive: false, cpu_times: {})
      end

      def command(client, cmd)
        client.send_cmd_and_wait(cmd, timeout: @timeout)
      end

      def connect(ws_url)
        client = Bidi2pdf::Bidi::Client.new(ws_url)
        client.start
        client.wait_until_open(timeout: @timeout)
        client
      end
    end
  end
end
