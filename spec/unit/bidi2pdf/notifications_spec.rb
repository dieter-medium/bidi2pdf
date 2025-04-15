# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::Notifications do
  let(:event_name) { "pdf.generated" }
  let(:payload) { { file: "output.pdf", duration: 123 } }
  let(:recorded_events) { [] }

  before { described_class.unsubscribe(event_name) }
  after { described_class.unsubscribe(event_name) }

  describe ".subscribe and .instrument" do
    before do
      described_class.subscribe(event_name) { |event| recorded_events << event }

      @result = described_class.instrument(event_name, payload) do |pl|
        pl[:extra] = "data"

        :done
      end

      @event = recorded_events.first
    end

    it "notifies one event" do
      expect(recorded_events.length).to eq(1)
    end

    it "sets correct event name" do
      expect(@event.name).to eq(event_name)
    end

    it "passes payload[:file]" do
      expect(@event.payload[:file]).to eq("output.pdf")
    end

    it "adds extra data to payload" do
      expect(@event.payload[:extra]).to eq("data")
    end

    it "returns result from block" do
      expect(@result).to eq(:done)
    end
  end

  describe "with multiple subscribers" do
    before do
      @called = []
      described_class.subscribe(/pdf\..*/) { @called << :regex }
      described_class.subscribe("pdf.generated") { @called << :string }
      described_class.instrument("pdf.generated", {})
    end

    it "calls the regex subscriber" do
      expect(@called).to include(:regex)
    end

    it "calls the string subscriber" do
      expect(@called).to include(:string)
    end
  end

  describe "unsubscribe" do
    it "does not notify unsubscribed listeners" do
      called = []
      block = described_class.subscribe(event_name) { called << true }
      described_class.unsubscribe(event_name, block)
      described_class.instrument(event_name, {})
      expect(called).to be_empty
    end
  end
end
