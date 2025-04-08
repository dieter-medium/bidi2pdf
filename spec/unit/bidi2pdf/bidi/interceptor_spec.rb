# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::Bidi::Interceptor do
  subject(:interceptor) { interceptor_class.new }

  # rubocop: disable Style/MultilineBlockChain
  let(:interceptor_class) do
    Class.new do
      class << self
        attr_writer :phases

        def phases
          @phases ||= ["beforeRequestSent"]
        end

        def events
          ["network.beforeRequestSent"]
        end
      end

      def context
        "test-context"
      end

      def url_patterns
        ["*"]
      end

      def process_interception(event_response, navigation_id, network_id, url)
        @intercepted = [event_response, navigation_id, network_id, url]
      end

      attr_reader :intercepted
    end.tap { |clazz| clazz.include described_class }
  end
  # rubocop: enable Style/MultilineBlockChain

  let(:client) { DummyClient.new(response) }
  let(:response) do
    {
      "result" => {
        "intercept" => "abc123"
      }
    }
  end

  describe "#register_with_client" do
    it "sends the addIntercept command to the client" do
      interceptor.register_with_client(client: client)

      expect(client.cmd_params).to eq(
                                     [
                                       Bidi2pdf::Bidi::Commands::AddIntercept.new(
                                         phases: ["beforeRequestSent"],
                                         context: "test-context",
                                         url_patterns: ["*"]
                                       )
                                     ]
                                   )
    end

    it "registers an event handler for the specified events" do
      interceptor.register_with_client(client: client)

      expect(client.event_params).to eq(["network.beforeRequestSent"])
    end

    it "stores the interceptor ID" do
      expect(interceptor.register_with_client(client: client).interceptor_id).to eq("abc123")
    end

    it "allows only valid phases" do
      interceptor_class.phases = ["XXXXX"]

      expect { interceptor.register_with_client(client: client) }.to raise_error(ArgumentError)
    end
  end

  describe "#handle_event" do
    before do
      interceptor.register_with_client(client: client)
    end

    let(:event_response) do
      {
        "params" => {
          "intercepts" => ["abc123"],
          "isBlocked" => true,
          "navigation" => "nav-id",
          "request" => {
            "request" => "req-id",
            "url" => "https://example.com"
          }
        }
      }
    end

    it "calls process_interception if event matches and is blocked" do
      interceptor.handle_event(event_response)

      expect(interceptor.intercepted).to eq([
                                              event_response["params"],
                                              "nav-id",
                                              "req-id",
                                              "https://example.com"
                                            ])
    end

    it "does nothing if the event is not blocked" do
      event_response["params"]["isBlocked"] = false

      expect(interceptor.intercepted).to be_nil
    end

    it "does nothing if intercepts (id) do not match" do
      event_response["params"]["intercepts"] = ["other-id"]

      interceptor.handle_event(event_response)

      expect(interceptor.intercepted).to be_nil
    end
  end
end
