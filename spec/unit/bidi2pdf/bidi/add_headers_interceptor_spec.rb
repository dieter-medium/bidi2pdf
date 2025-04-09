# frozen_string_literal: true

require "spec_helper"
require "testcontainers"

RSpec.describe Bidi2pdf::Bidi::AddHeadersInterceptor do
  subject(:interceptor) { described_class.new(headers: [{ name: "X-Test", value: "test" }], url_patterns: ["*"], context: "my-id") }

  let(:client) { DummyClient.new(response) }
  let(:register_cmd_class) { Bidi2pdf::Bidi::Commands::AddIntercept }
  let(:expected_events) { ["network.beforeRequestSent"] }
  let(:response) do
    {
      "result" => {
        "intercept" => "abc123"
      }
    }
  end

  it_behaves_like "a interceptor"

  describe "#process_interception" do
    it "adds the headers to the request" do
      interceptor.register_with_client(client: client)

      interceptor.process_interception("dummy", "dummy", "dummy", "dummy")

      expect(client.cmd_params).to eq([Bidi2pdf::Bidi::Commands::NetworkContinue.new(request: "dummy", headers: [{ name: "X-Test", value: { type: "string", value: "test" } }])])
    end
  end
end
