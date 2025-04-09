# frozen_string_literal: true

RSpec.shared_examples "a interceptor" do
  describe "class methods" do
    it "responds to .phases" do
      expect(described_class).to respond_to(:phases)
    end

    it "responds to .events" do
      expect(described_class).to respond_to(:events)
    end
  end

  describe "instance methods" do
    it "responds to #context" do
      expect(subject).to respond_to(:context)
    end

    it "responds to #url_patterns" do
      expect(subject).to respond_to(:url_patterns)
    end

    it "responds to #process_interception" do
      expect(subject).to respond_to(:process_interception)
    end

    it "responds to #register_with_client" do
      expect(subject).to respond_to(:register_with_client)
    end

    it "responds to #validate_phases!" do
      expect(subject).to respond_to(:validate_phases!)
    end
  end

  describe "#register_with_client" do
    it "registers the interceptor with the client" do
      interceptor.register_with_client(client: client)

      expect(client.cmd_params.first).to be_a(register_cmd_class)
    end

    it "registers event handlers for the specified events" do
      interceptor.register_with_client(client: client)

      expect(client.event_params).to eq(expected_events)
    end
  end
end
