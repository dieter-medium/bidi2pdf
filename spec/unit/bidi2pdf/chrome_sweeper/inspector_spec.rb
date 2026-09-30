# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::ChromeSweeper::Inspector do
  subject(:inspector) { described_class.new(clock: -> { 1_000.0 }, client_factory: ->(_url) { client }) }

  # A session's BiDi endpoint: answers per method name; +timeouts+ lists how many times a method
  # times out before it answers (:always never answers).
  let(:client) do
    Struct.new(:answers, :timeouts, :closed) do
      def send_cmd_and_wait(cmd, timeout:)
        pending = timeouts[cmd.method_name]
        raise Bidi2pdf::CmdTimeoutError, "timeout after #{timeout}" if pending == :always

        if pending.to_i.positive?
          timeouts[cmd.method_name] -= 1
          raise Bidi2pdf::CmdTimeoutError, "timeout after #{timeout}"
        end

        { "result" => answers.fetch(cmd.method_name) }
      end

      def close = self.closed = true
    end.new(
      {
        "browsingContext.getTree" => { "contexts" => [{ "context" => "tab-1", "url" => "data:text/html,secret" }] },
        "script.evaluate" => { "result" => { "type" => "number", "value" => 400_000.0 } },
        "goog:cdp.sendCommand" => { "result" => { "processInfo" => [{ "id" => 7, "type" => "renderer", "cpuTime" => 1.5 },
                                                                    { "id" => 6, "type" => "browser", "cpuTime" => 9.0 }] } }
      },
      {}, false
    )
  end

  let(:entry) { Bidi2pdf::ChromedriverApi::Entry.new(id: "abc", websocket_url: "ws://remote-chrome:3000/session/abc", process_id: 1) }

  it "ages a session by its first tab's time origin" do
    expect(inspector.examine(entry).age).to eq(600.0)
  end

  it "prefers the registry's time" do
    expect(inspector.examine(entry, recorded_at: 900).then { |info| [info.age, info.source] }).to eq([100.0, :registry])
  end

  it "counts the tabs" do
    expect(inspector.examine(entry).tabs).to eq(1)
  end

  it "reports renderer CPU times only" do
    expect(inspector.examine(entry).cpu_times).to eq(7 => 1.5)
  end

  it "never returns a tab's URL" do
    expect(inspector.examine(entry).to_h.to_s).not_to include("secret")
  end

  it "retries the first command once - a freshly attached connection may not answer it" do
    client.timeouts["browsingContext.getTree"] = 1

    expect(inspector.examine(entry).responsive).to be(true)
  end

  it "gives a tab a second chance to evaluate" do
    client.timeouts["script.evaluate"] = 1

    expect(inspector.examine(entry).responsive).to be(true)
  end

  it "reports a session whose tab never evaluates anything as unresponsive" do
    client.timeouts["script.evaluate"] = :always

    expect(inspector.examine(entry).responsive).to be(false)
  end

  it "reports a session that does not answer at all as unresponsive" do
    client.timeouts["browsingContext.getTree"] = :always

    expect(inspector.examine(entry).responsive).to be(false)
  end

  it "reports a session it cannot connect to as unresponsive" do
    unreachable = described_class.new(client_factory: ->(_url) { raise Bidi2pdf::WebsocketError, "refused" })

    expect(unreachable.examine(entry).responsive).to be(false)
  end

  it "closes its own connection" do
    inspector.examine(entry)

    expect(client.closed).to be(true)
  end
end
