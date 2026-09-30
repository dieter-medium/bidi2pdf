# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::ChromedriverApi do
  subject(:api) { described_class.new("http://remote-chrome:3000/session", http: http) }

  let(:requests) { [] }
  let(:response) { [200, ""] }
  let(:http) do
    lambda do |method, url|
      requests << [method, url]
      response
    end
  end

  describe "listing sessions" do
    let(:response) do
      [200, JSON.generate("value" => [{ "id" => "abc", "capabilities" => { "webSocketUrl" => "ws://remote-chrome:3000/session/abc",
                                                                           "goog:processID" => 42 } }])]
    end

    it "asks chromedriver's /sessions endpoint" do
      api.sessions

      expect(requests).to eq([[:get, "http://remote-chrome:3000/sessions"]])
    end

    it "returns each session's id, WebSocket URL and process id" do
      expect(api.sessions).to eq([described_class::Entry.new(id: "abc", websocket_url: "ws://remote-chrome:3000/session/abc", process_id: 42)])
    end

    it "keeps a URL base prefix" do
      described_class.new("http://host:9515/wd/hub/session", http: http).sessions

      expect(requests).to eq([[:get, "http://host:9515/wd/hub/sessions"]])
    end
  end

  it "raises when chromedriver does not list its sessions" do
    failing = described_class.new("http://remote-chrome:3000/session", http: ->(*) { [500, ""] })

    expect { failing.sessions }.to raise_error(Bidi2pdf::Error, /500/)
  end

  describe "deleting a session" do
    it "sends DELETE to the session's URL" do
      api.delete_session("abc")

      expect(requests).to eq([[:delete, "http://remote-chrome:3000/session/abc"]])
    end

    it "reports a session that is gone now as closed" do
      expect(api.delete_session("abc")).to eq(:closed)
    end

    context "when chromedriver no longer has the session" do
      let(:response) { [404, ""] }

      it "reports it as gone" do
        expect(api.delete_session("abc")).to eq(:gone)
      end
    end

    context "when chromedriver fails" do
      let(:response) { [500, ""] }

      it "reports a failure" do
        expect(api.delete_session("abc")).to eq(:failed)
      end
    end
  end
end
