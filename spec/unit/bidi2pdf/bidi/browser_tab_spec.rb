# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::Bidi::BrowserTab do
  subject(:browser_tab) { described_class.new client, browsing_context_id, "dummy-user-context-id" }

  let(:browsing_context_id) { "dummy-browsing-content-id" }
  let(:client) { DummyClient.new(response) }
  let(:response) do
    {
      "result" => {
        "context" => "abc123"
      }
    }
  end

  before do
    @old_time_provider = Bidi2pdf::Bidi::Commands::SetTabCookie.time_provider
    Bidi2pdf::Bidi::Commands::SetTabCookie.time_provider = -> { 1000 }
  end

  after do
    Bidi2pdf::Bidi::Commands::SetTabCookie.time_provider = @old_time_provider
  end

  describe "#create_browser_tab" do
    it "creates a new browser tab" do
      expect(browser_tab.create_browser_tab).to be_a described_class
    end
  end

  describe "#set_cookie" do
    it "sends the setCookie command to the client" do
      browser_tab.set_cookie(
        name: "test",
        value: "testvalue",
        domain: "example.com",
        path: "/hello",
        secure: true,
        http_only: false,
        same_site: "strict",
        ttl: 60
      )

      expect(client.cmd_params.first).to eq(Bidi2pdf::Bidi::Commands::SetTabCookie.new(
        browsing_context_id: browsing_context_id,
        name: "test",
        value: "testvalue",
        domain: "example.com",
        path: "/hello",
        secure: true,
        http_only: false,
        same_site: "strict",
        ttl: 60
      ))
    end
  end

  describe "#navigate_to" do
    it "sends the openPage command to the client" do
      browser_tab.navigate_to("https://example.com")

      expect(client.cmd_params.first).to eq(Bidi2pdf::Bidi::Commands::BrowsingContextNavigate.new(url: "https://example.com", context: browsing_context_id))
    end

    it "registers an event handler for the network events" do
      browser_tab.navigate_to("https://example.com")
      expect(client.event_params(0)).to include("network.responseStarted", "network.responseCompleted", "network.fetchError")
    end

    it "registers an event handler for the log events" do
      browser_tab.navigate_to("https://example.com")
      expect(client.event_params(1)).to include("log.entryAdded")
    end

    it "registers an event handler navigation failure events" do
      browser_tab.navigate_to("https://example.com")
      expect(client.event_params(2)).to include("browsingContext.navigationFailed")
    end

    it "raises an error, when url is invalid" do
      expect { browser_tab.navigate_to("hello world") }.to raise_error(Bidi2pdf::NavigationError)
    end

    context "when the navigate response carries a navigation id" do
      let(:response) { { "result" => { "context" => "abc123", "navigation" => "nav-1" } } }

      def seed_completed_request(navigation:, http_status_code:)
        browser_tab.network_events.events["req-1"] = Bidi2pdf::Bidi::NetworkEvent.new(
          id: "req-1", url: "https://example.com", timestamp: 1000.0, timing: nil,
          state: "network.responseCompleted", http_status_code: http_status_code, navigation: navigation
        )
      end

      it "raises NavigationNotFoundError when the correlated request completed with a 404" do
        seed_completed_request(navigation: "nav-1", http_status_code: 404)

        expect { browser_tab.navigate_to("https://example.com") }.to raise_error(Bidi2pdf::NavigationNotFoundError)
      end

      it "raises NavigationError when the correlated request completed with another error status" do
        seed_completed_request(navigation: "nav-1", http_status_code: 500)

        expect { browser_tab.navigate_to("https://example.com") }.to raise_error(Bidi2pdf::NavigationError, /HTTP 500/)
      end

      it "does not raise when the correlated request completed successfully" do
        seed_completed_request(navigation: "nav-1", http_status_code: 200)

        expect { browser_tab.navigate_to("https://example.com") }.not_to raise_error
      end

      it "does not raise when no network event is correlated to this navigation" do
        seed_completed_request(navigation: "some-other-navigation", http_status_code: 404)

        expect { browser_tab.navigate_to("https://example.com") }.not_to raise_error
      end
    end
  end

  describe "#render_html_content" do
    it "sends the openPage command to the client" do
      browser_tab.render_html_content("<html></html>")

      expect(client.cmd_params.first).to eq(Bidi2pdf::Bidi::Commands::BrowsingContextNavigate.new(url: "data:text/html;charset=utf-8;base64,PGh0bWw+PC9odG1sPg==", context: browsing_context_id))
    end
  end

  describe "#execute_script" do
    it "sends the executeScript command to the client" do
      browser_tab.execute_script("console.log('test')")
      expect(client.cmd_params.first).to eq(Bidi2pdf::Bidi::Commands::ScriptEvaluate.new(context: browsing_context_id, expression: "console.log('test')"))
    end
  end

  describe "#print" do
    let(:response) do
      {
        "result" => {
          "data" => "some base64 data"
        }
      }
    end

    let(:tmp_path) { random_tmp_dir }
    let(:pdf_path) { File.join(tmp_path, "test.pdf") }

    before do
      FileUtils.mkdir_p(tmp_path)
    end

    after do
      FileUtils.rm_f(tmp_path)
    end

    it "sends the print command to the client" do
      browser_tab.print
      expect(client.cmd_params.first).to eq(Bidi2pdf::Bidi::Commands::BrowsingContextPrint.new(context: browsing_context_id, print_options: nil))
    end

    it "returns the pdf data, when no filename is given" do
      expect(browser_tab.print).to eq("some base64 data")
    end

    it "yields the pdf data, when a block is given" do
      expect { |b| browser_tab.print(&b) }.to yield_with_args("some base64 data")
    end

    it "saves the pdf data to the given filename" do
      browser_tab.print(pdf_path)
      expect(File).to exist(pdf_path)
    end
  end

  describe "#screenshot" do
    let(:response) do
      {
        "result" => {
          "data" => "some base64 image data"
        }
      }
    end

    let(:tmp_path) { random_tmp_dir }
    let(:png_path) { File.join(tmp_path, "test.png") }

    before do
      FileUtils.mkdir_p(tmp_path)
    end

    after do
      FileUtils.rm_f(tmp_path)
    end

    it "sends the captureScreenshot command to the client" do
      browser_tab.screenshot
      expect(client.cmd_params.first).to eq(Bidi2pdf::Bidi::Commands::CaptureScreenshot.new(context: browsing_context_id))
    end

    it "returns the image data, when no filename is given" do
      expect(browser_tab.screenshot).to eq("some base64 image data")
    end

    it "yields the image data, when a block is given" do
      expect { |b| browser_tab.screenshot(&b) }.to yield_with_args("some base64 image data")
    end

    it "saves the image data to the given filename" do
      browser_tab.screenshot(png_path)
      expect(File).to exist(png_path)
    end
  end

  describe "#set_viewport" do
    it "sends the setViewport command to the client" do
      browser_tab.set_viewport(width: 1280, height: 800)

      expect(client.cmd_params.first).to eq(Bidi2pdf::Bidi::Commands::SetViewport.new(context: browsing_context_id, width: 1280, height: 800))
    end
  end
end
