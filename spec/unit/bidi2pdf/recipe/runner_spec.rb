# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::Recipe::Runner do
  let(:tab) { instance_double(Bidi2pdf::Bidi::BrowserTab) }
  let(:collector) { instance_double(Bidi2pdf::ResultCollector, console: [], network_failures: []) }

  def success(value)
    { "type" => "success", "result" => { "type" => value.is_a?(String) ? "string" : "boolean", "value" => value } }
  end

  def recipe(data)
    Bidi2pdf::Recipe.new(data)
  end

  def runner(data)
    described_class.new(recipe: recipe(data), tab: tab, collector: collector)
  end

  describe "#run_actions" do
    it "returns one ok entry per action" do
      allow(tab).to receive_messages(execute_script: success(true), wait_until_network_idle: nil)
      data = { "actions" => [{ "wait_for" => { "selector" => "#x" } }, { "wait_network_idle" => { "timeout" => 5 } }] }

      entries = runner(data).run_actions

      expect(entries).to eq([{ index: 0, type: "wait_for", ok: true, duration_ms: entries[0][:duration_ms] },
                              { index: 1, type: "wait_network_idle", ok: true, duration_ms: entries[1][:duration_ms] }])
    end

    it "calls wait_until_network_idle with the given timeout" do
      allow(tab).to receive(:wait_until_network_idle)

      runner({ "actions" => [{ "wait_network_idle" => { "timeout" => 5 } }] }).run_actions

      expect(tab).to have_received(:wait_until_network_idle).with(timeout: 5)
    end

    it "calls set_viewport with the given dimensions" do
      allow(tab).to receive(:set_viewport)

      runner({ "actions" => [{ "set_viewport" => { "width" => 1280, "height" => 900 } }] }).run_actions

      expect(tab).to have_received(:set_viewport).with(width: 1280, height: 900, device_pixel_ratio: nil)
    end

    it "calls inject_style with the given content" do
      allow(tab).to receive(:inject_style)

      runner({ "actions" => [{ "inject_style" => { "content" => "body{}" } }] }).run_actions

      expect(tab).to have_received(:inject_style).with(url: nil, content: "body{}", id: nil)
    end

    it "stores an evaluate result under state when assign is given" do
      allow(tab).to receive(:execute_script).and_return(success("Invoice #123"))

      result = runner({ "actions" => [{ "evaluate" => { "script" => "document.title", "assign" => "page_title" } }] })
      result.run_actions

      expect(result.state).to eq("page_title" => "Invoice #123")
    end

    # rubocop:disable-next RSpec/MultipleExpectations
    it "raises SelectorNotFoundError when wait_for's script never succeeds" do
      allow(tab).to receive(:execute_script).and_return({ "type" => "exception" })

      expect { runner({ "actions" => [{ "wait_for" => { "selector" => "#missing", "timeout" => 1 } }] }).run_actions }
        .to raise_error(Bidi2pdf::Recipe::Runner::StepFailure) { |error| expect(error.cause).to be_a(Bidi2pdf::SelectorNotFoundError) }
    end

    it "stops at the first failing action and reports it not-ok in the entries" do
      allow(tab).to receive(:execute_script).and_return({ "type" => "exception" })
      data = { "actions" => [{ "click" => { "selector" => "#missing" } }, { "evaluate" => { "script" => "1" } }] }

      begin
        runner(data).run_actions
      rescue Bidi2pdf::Recipe::Runner::StepFailure => e
        failure = e
      end

      expect(failure.entries).to eq([{ index: 0, type: "click", ok: false, duration_ms: failure.entries[0][:duration_ms] }])
    end
  end

  describe "#run_assertions" do
    it "passes selector_exists when the selector is present" do
      allow(tab).to receive(:execute_script).and_return(success(true))

      entries = runner({ "assert" => [{ "selector_exists" => { "selector" => "#total" } }] }).run_assertions

      expect(entries).to eq([{ index: 0, type: "selector_exists", ok: true, duration_ms: entries[0][:duration_ms], details: { selector: "#total" } }])
    end

    # rubocop:disable-next RSpec/MultipleExpectations
    it "raises with structured details when selector_exists fails" do
      allow(tab).to receive(:execute_script).and_return(success(false))

      expect { runner({ "assert" => [{ "selector_exists" => { "selector" => "#total" } }] }).run_assertions }
        .to raise_error(Bidi2pdf::Recipe::Runner::StepFailure) do |error|
          expect(error.cause.details).to eq(selector: "#total", assertion: "selector_exists")
        end
    end

    it "passes text_present when the body text includes the expected substring" do
      allow(tab).to receive(:execute_script).and_return(success("Invoice #123 total due"))

      expect(runner({ "assert" => [{ "text_present" => { "text" => "Invoice #123" } }] }).run_assertions.first[:ok]).to be true
    end

    it "fails text_present when the body text does not include it" do
      allow(tab).to receive(:execute_script).and_return(success("nothing here"))

      expect { runner({ "assert" => [{ "text_present" => { "text" => "Invoice #123" } }] }).run_assertions }
        .to raise_error(Bidi2pdf::Recipe::Runner::StepFailure)
    end

    it "passes no_console_errors when the collector saw no error-level entries" do
      allow(collector).to receive(:console).and_return([{ level: :warn, text: "meh" }])

      expect(runner({ "assert" => [{ "no_console_errors" => true }] }).run_assertions.first[:ok]).to be true
    end

    # rubocop:disable-next RSpec/MultipleExpectations
    it "fails no_console_errors and includes the errors in details when the collector saw one" do
      allow(collector).to receive(:console).and_return([{ level: "error", text: "boom" }])

      expect { runner({ "assert" => [{ "no_console_errors" => true }] }).run_assertions }
        .to raise_error(Bidi2pdf::Recipe::Runner::StepFailure) { |error| expect(error.cause.details[:console_errors]).to eq([{ level: "error", text: "boom" }]) }
    end

    it "passes no_network_failures when the collector saw none" do
      expect(runner({ "assert" => [{ "no_network_failures" => true }] }).run_assertions.first[:ok]).to be true
    end

    it "fails no_network_failures when the collector saw one" do
      allow(collector).to receive(:network_failures).and_return([{ url: "https://x/app.css", method: "GET", status: nil, state: "error" }])

      expect { runner({ "assert" => [{ "no_network_failures" => true }] }).run_assertions }.to raise_error(Bidi2pdf::Recipe::Runner::StepFailure)
    end

    it "passes fonts_loaded when no font errored" do
      allow(tab).to receive(:execute_script).and_return(success(true))

      expect(runner({ "assert" => [{ "fonts_loaded" => true }] }).run_assertions.first[:ok]).to be true
    end

    describe "PDF assertions" do
      let(:pdf_bytes) { File.binread(fixture_file("sample.pdf")) }

      it "page_count passes on an exact match" do
        instance = runner({ "assert" => [{ "page_count" => Bidi2pdf::PdfInspection.page_count(pdf_bytes) }] })
        instance.pdf_bytes = pdf_bytes

        expect(instance.run_assertions.first[:ok]).to be true
      end

      # rubocop:disable-next RSpec/MultipleExpectations
      it "page_count fails on a mismatch, with expected/actual in details" do
        instance = runner({ "assert" => [{ "page_count" => 999 }] })
        instance.pdf_bytes = pdf_bytes

        expect { instance.run_assertions }.to raise_error(Bidi2pdf::Recipe::Runner::StepFailure) do |error|
          expect(error.cause.details).to eq(expected: 999, actual: Bidi2pdf::PdfInspection.page_count(pdf_bytes), assertion: "page_count")
        end
      end

      it "page_count passes a {min:, max:} range" do
        instance = runner({ "assert" => [{ "page_count" => { "min" => 1, "max" => 10 } }] })
        instance.pdf_bytes = pdf_bytes

        expect(instance.run_assertions.first[:ok]).to be true
      end

      it "pdf_not_blank passes for a real, non-empty PDF" do
        instance = runner({ "assert" => [{ "pdf_not_blank" => true }] })
        instance.pdf_bytes = pdf_bytes

        expect(instance.run_assertions.first[:ok]).to be true
      end

      it "pdf_not_blank fails when there is no PDF at all" do
        instance = runner({ "assert" => [{ "pdf_not_blank" => true }] })

        expect { instance.run_assertions }.to raise_error(Bidi2pdf::Recipe::Runner::StepFailure)
      end
    end
  end
end
