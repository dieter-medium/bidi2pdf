# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::ResultCollector do
  let(:collector) { described_class.new(requested_url: "https://example.com/invoice/123", command: "render", output: "out.pdf") }

  def network_event(id:, url:, state: "completed", http_status_code: 200, navigation: nil, start_timestamp: 1000, http_method: "GET")
    event = Bidi2pdf::Bidi::NetworkEvent.new(
      id: id, url: url, timestamp: start_timestamp, timing: nil, state: "network.beforeRequestSent",
      http_status_code: nil, http_method: http_method, navigation: navigation
    )
    event.update_state("network.#{state}", timestamp: start_timestamp + 5, http_status_code: http_status_code) unless state == "beforeRequestSent"
    event
  end

  it "returns a successful Result when the block does not raise" do
    expect(collector.around { nil }).to be_ok
  end

  it "carries the command/output through to the Result" do
    result = collector.around { nil }

    expect([result.command, result.output]).to eq(["render", "out.pdf"])
  end

  it "measures duration_ms" do
    expect(collector.around { nil }.duration_ms).to be_a(Integer)
  end

  it "never raises, even when the block does" do
    expect do
      collector.around { raise Bidi2pdf::NavigationTimeoutError, "Navigation did not complete within 60 seconds" }
    end.not_to raise_error
  end

  it "returns a not-ok Result for whatever the block raised" do
    result = collector.around { raise Bidi2pdf::NavigationTimeoutError, "Navigation did not complete within 60 seconds" }

    expect(result).not_to be_ok
  end

  it "describes the raised error on the failing Result" do
    result = collector.around { raise Bidi2pdf::NavigationTimeoutError, "Navigation did not complete within 60 seconds" }

    expect(result.error).to eq(
      code: "NAVIGATION_TIMEOUT",
      message: "Navigation did not complete within 60 seconds",
      retryable: true,
      hint: Bidi2pdf::NavigationTimeoutError.new.hint,
      details: {}
    )
  end

  it "captures console entries emitted during the block" do
    result = collector.around do
      Bidi2pdf.notification_service.instrument("browser_console_log_received.bidi2pdf",
                                               level: :error, text: "boom", args: [], stack_trace: nil, timestamp: nil)
    end

    expect(result.console).to eq([{ level: :error, text: "boom" }])
  end

  it "exposes #console/#network_failures live, before the block finishes (used by Recipe::Runner's assertions)" do
    seen_console = nil

    collector.around do
      Bidi2pdf.notification_service.instrument("browser_console_log_received.bidi2pdf",
                                               level: :error, text: "boom", args: [], stack_trace: nil, timestamp: nil)
      seen_console = collector.console
    end

    expect(seen_console).to eq([{ level: :error, text: "boom" }])
  end

  # rubocop:disable-next RSpec/MultipleExpectations
  it "captures the printed PDF bytes and computes bytes/sha256/pages from that one real PDF" do
    pdf_bytes = File.binread(fixture_file("sample.pdf"))
    pdf_base64 = Base64.strict_encode64(pdf_bytes)

    result = collector.around do
      Bidi2pdf.notification_service.instrument("print.bidi2pdf") { |payload| payload[:pdf_base64] = pdf_base64 }
    end

    expect(result.bytes).to eq(pdf_bytes.bytesize)
    expect(result.sha256).to eq(Digest::SHA256.hexdigest(pdf_bytes))
    expect(result.pages).to be_a(Integer)
  end

  # rubocop:disable-next RSpec/MultipleExpectations
  it "derives navigation.final_url/status from the last hop of the winning navigation, and reports network_failures" do
    ok_event = network_event(id: "1", url: "https://example.com/invoice/123", navigation: "nav-1", start_timestamp: 1000)
    redirect_event = network_event(id: "2", url: "https://example.com/invoice/123/", navigation: "nav-1", start_timestamp: 2000)
    failed_event = network_event(id: "3", url: "https://example.com/app.css", state: "fetchError", http_status_code: nil, start_timestamp: 1500)

    result = collector.around do
      [ok_event, redirect_event, failed_event].each do |event|
        Bidi2pdf.notification_service.instrument("network_event_received.bidi2pdf") { |payload| payload[:event] = event }
      end
    end

    expect(result.navigation).to eq(requested_url: "https://example.com/invoice/123", final_url: "https://example.com/invoice/123/", status: 200)
    expect(result.network_failures).to eq([{ url: "https://example.com/app.css", method: "GET", status: nil, state: "error" }])
  end

  it "falls back to the requested_url when no network event carries a navigation id" do
    result = collector.around { nil }

    expect(result.navigation).to eq(requested_url: "https://example.com/invoice/123", final_url: "https://example.com/invoice/123", status: nil)
  end

  describe "the pages/pdf-reader warning" do
    after { Bidi2pdf::PdfInspection.reset_for_testing! }

    it "stays empty when there is no PDF at all" do
      Bidi2pdf::PdfInspection.reset_for_testing!
      allow(Bidi2pdf::PdfInspection).to receive(:require).with("pdf-reader").and_raise(LoadError)

      expect(collector.around { nil }.warnings).to eq([])
    end

    it "appears once there is a PDF and pdf-reader is unavailable" do
      Bidi2pdf::PdfInspection.reset_for_testing!
      allow(Bidi2pdf::PdfInspection).to receive(:require).with("pdf-reader").and_raise(LoadError)

      result = collector.around do
        Bidi2pdf.notification_service.instrument("print.bidi2pdf") { |payload| payload[:pdf_base64] = Base64.strict_encode64("%PDF-1.4") }
      end

      expect(result.warnings).to eq(["pages requires the pdf-reader gem"])
    end
  end

  it "only removes its own subscriptions, leaving a concurrently active subscriber (e.g. LoggingSubscriber) intact" do
    other_calls = []
    other = Bidi2pdf.notification_service.subscribe("print.bidi2pdf") { |event| other_calls << event }

    collector.around do
      Bidi2pdf.notification_service.instrument("print.bidi2pdf") { |payload| payload[:pdf_base64] = nil }
    end

    expect(other_calls.size).to eq(1)
  ensure
    Bidi2pdf.notification_service.unsubscribe("print.bidi2pdf", other)
  end
end
