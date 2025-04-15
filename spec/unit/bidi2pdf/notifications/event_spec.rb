# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::Notifications::Event do
  let(:event_name) { "pdf.generated" }

  before do
    @captured = []
    Bidi2pdf::Notifications.subscribe(event_name) { |e| @captured << e }

    begin
      Bidi2pdf::Notifications.instrument(event_name) { raise StandardError, "Boom" }
    rescue StandardError
      # expected
    end
  end

  after { Bidi2pdf::Notifications.unsubscribe(event_name) }

  it "captures exception class and message in payload" do
    expect(@captured.first.payload[:exception]).to include("StandardError", "Boom")
  end

  it "captures the exception object" do
    expect(@captured.first.payload[:exception_object]).to be_a(StandardError)
  end

  it "records duration of block execution" do
    event = described_class.new(event_name, nil, nil, "1234", {})
    event.record { sleep 0.01 }
    expect(event.duration).to be >= 10
  end
end
