# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Bidi2pdf::Notifications::JsonSubscriber do
  let(:io) { StringIO.new }
  let!(:subscriber) { described_class.new(io: io) }

  def lines
    io.string.each_line.map { |line| JSON.parse(line, symbolize_names: true) }
  end

  after { subscriber.unsubscribe }

  it "writes one JSON object per line" do
    Bidi2pdf.notification_service.instrument("navigate_to.bidi2pdf", url: "https://example.com")

    expect(lines.size).to eq(1)
  end

  it "includes schema_version and t_ms on every event" do
    Bidi2pdf.notification_service.instrument("navigate_to.bidi2pdf", url: "https://example.com")

    expect(lines.first).to include(schema_version: 1, t_ms: kind_of(Integer))
  end

  it "emits a navigate event with the requested url" do
    Bidi2pdf.notification_service.instrument("navigate_to.bidi2pdf", url: "https://example.com")

    expect(lines.first).to include(event: "navigate", url: "https://example.com")
  end

  it "emits a console event with level/text" do
    Bidi2pdf.notification_service.instrument("browser_console_log_received.bidi2pdf",
                                             level: "error", text: "boom", args: [], stack_trace: nil, timestamp: nil)

    expect(lines.first).to include(event: "console", level: "error", text: "boom")
  end

  it "emits a page_loaded event" do
    Bidi2pdf.notification_service.instrument("page_loaded.bidi2pdf")

    expect(lines.first).to include(event: "page_loaded")
  end

  it "emits emit_result as the final result event, matching the Result's own #to_h" do
    result = Bidi2pdf::Result.success(command: "render")

    subscriber.emit_result(result)

    expect(lines.first).to eq(schema_version: 1, t_ms: lines.first[:t_ms], event: "result", result: result.to_h)
  end

  it "stops receiving events once unsubscribed" do
    subscriber.unsubscribe
    Bidi2pdf.notification_service.instrument("navigate_to.bidi2pdf", url: "https://example.com")

    expect(lines).to eq([])
  end
end
