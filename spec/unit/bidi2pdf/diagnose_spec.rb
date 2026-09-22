# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::Diagnose do
  let(:tab) { instance_double(Bidi2pdf::Bidi::BrowserTab) }

  def success(value)
    { "type" => "success", "result" => { "type" => "string", "value" => value } }
  end

  describe "#call" do
    it "parses the page script's JSON result" do
      allow(tab).to receive(:execute_script).and_return(
        success({ title: "Invoice #123", url: "https://example.com/invoice/123", lang: "en" }.to_json)
      )

      expect(described_class.new(tab: tab).call[:page]).to eq("title" => "Invoice #123", "url" => "https://example.com/invoice/123", "lang" => "en")
    end

    it "parses the fonts script's JSON result" do
      allow(tab).to receive(:execute_script).and_return(success({ status: "loaded", loaded: ["Inter 400 normal"], failed: [] }.to_json))

      expect(described_class.new(tab: tab).call[:fonts]).to eq("status" => "loaded", "loaded" => ["Inter 400 normal"], "failed" => [])
    end

    it "parses the print_media script's JSON result" do
      allow(tab).to receive(:execute_script).and_return(
        success({ stylesheets_with_print_rules: ["a.css"], page_rules: [], break_inside_avoid_count: 3, fixed_or_sticky_elements: [],
                  unreadable_stylesheets: [] }.to_json)
      )

      expect(described_class.new(tab: tab).call[:print_media]["break_inside_avoid_count"]).to eq(3)
    end

    it "parses the paged_js script's JSON result" do
      allow(tab).to receive(:execute_script).and_return(success({ detected: true, ready: true, pages: 3 }.to_json))

      expect(described_class.new(tab: tab).call[:paged_js]).to eq("detected" => true, "ready" => true, "pages" => 3)
    end

    it "returns nil for a collector whose script threw, instead of raising" do
      allow(tab).to receive(:execute_script).and_return({ "type" => "exception", "exceptionDetails" => { "text" => "boom" } })

      expect { described_class.new(tab: tab).call }.not_to raise_error
    end

    it "returns nil for a collector whose script threw" do
      allow(tab).to receive(:execute_script).and_return({ "type" => "exception", "exceptionDetails" => { "text" => "boom" } })

      expect(described_class.new(tab: tab).call[:page]).to be_nil
    end

    it "returns nil rather than raising when the script result is not valid JSON" do
      allow(tab).to receive(:execute_script).and_return(success("not json"))

      expect { described_class.new(tab: tab).call }.not_to raise_error
    end

    it "sends each script through execute_script" do
      allow(tab).to receive(:execute_script).and_return(success("{}"))

      described_class.new(tab: tab).call

      expect(tab).to have_received(:execute_script).exactly(4).times
    end
  end
end
