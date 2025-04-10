# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::Bidi::AuthInterceptor do
  subject(:interceptor) { described_class.new(username: "test", password: "<PASSWORD>", url_patterns: ["*"], context: "my-id") }

  let(:client) { DummyClient.new(response) }
  let(:register_cmd_class) { Bidi2pdf::Bidi::Commands::AddIntercept }
  let(:expected_events) { ["network.authRequired"] }
  let(:response) do
    {
      "result" => {
        "intercept" => "abc123"
      }
    }
  end

  it_behaves_like "a interceptor"

  describe "#process_interception" do
    context "with valid credentials" do
      it "continues the request" do
        interceptor.register_with_client(client: client)
        interceptor.process_interception("dummy", "dummy", "my_network_id", "dummy")

        expect(client.cmd_params).to eq([Bidi2pdf::Bidi::Commands::ProvideCredentials.new(request: "my_network_id", username: "test", password: "<PASSWORD>")])
      end
    end

    context "with invalid credentials" do
      it "cancels the request" do
        interceptor.register_with_client(client: client)
        interceptor.process_interception("dummy", "dummy", "my_network_id", "dummy")

        # is triggered by the second attemp
        interceptor.process_interception("dummy", "dummy", "my_network_id", "dummy")

        expect(client.cmd_params).to eq([Bidi2pdf::Bidi::Commands::CancelAuth.new(request: "my_network_id")])
      end
    end
  end
end
