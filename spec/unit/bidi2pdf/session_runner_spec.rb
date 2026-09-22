# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::SessionRunner do
  let(:client) { instance_double(Bidi2pdf::Bidi::Client, on_close: nil) }
  let(:session) { instance_double(Bidi2pdf::Bidi::Session, start: nil, client: client, browser: browser, status: {}, user_contexts: []) }
  let(:browser) { instance_double(Bidi2pdf::Bidi::Browser, create_user_context: user_context) }
  let(:user_context) { instance_double(Bidi2pdf::Bidi::UserContext, create_browser_window: window, close: nil) }
  let(:window) { instance_double(Bidi2pdf::Bidi::BrowserTab, create_browser_tab: tab, close: nil) }
  let(:tab) do
    instance_double(Bidi2pdf::Bidi::BrowserTab,
                    set_cookie: nil, add_headers: nil, basic_auth: nil, navigate_to: nil, render_html_content: nil,
                    wait_until_network_idle: nil, wait_until_page_loaded: nil, log_network_traffic: nil, print: nil, close: nil)
  end

  def runner(**overrides)
    described_class.new(session: session, url: "https://example.com", inputfile: nil, output: "out.pdf", **overrides)
  end

  describe "#run" do
    it "navigates to the given URL" do
      runner.run

      expect(tab).to have_received(:navigate_to).with("https://example.com")
    end

    it "prints to the given output" do
      runner.run

      expect(tab).to have_received(:print).with("out.pdf", print_options: {})
    end

    it "closes the tab, window and user context afterward" do
      runner.run

      expect([tab, window, user_context]).to all(have_received(:close))
    end

    it "sets a cookie for each given cookie" do
      runner(cookies: { "session" => "abc" }).run

      expect(tab).to have_received(:set_cookie).with(hash_including(name: "session", value: "abc"))
    end

    it "waits for network idle only when requested" do
      runner(wait_network_idle: true).run

      expect(tab).to have_received(:wait_until_network_idle)
    end

    it "does not wait for network idle when not requested" do
      runner.run

      expect(tab).not_to have_received(:wait_until_network_idle)
    end

    it "reads and renders the input file when no url is given" do
      html_file = fixture_file("sample.html")

      runner(url: nil, inputfile: html_file).run

      expect(tab).to have_received(:render_html_content).with(File.read(html_file))
    end
  end

  describe "#run_diagnose" do
    it "navigates to the given URL" do
      runner.run_diagnose

      expect(tab).to have_received(:navigate_to).with("https://example.com")
    end

    it "does not print" do
      runner.run_diagnose

      expect(tab).not_to have_received(:print)
    end

    it "does not log network traffic (no report-file side effect)" do
      runner.run_diagnose

      expect(tab).not_to have_received(:log_network_traffic)
    end

    it "leaves the tab open for the caller" do
      runner.run_diagnose

      expect(tab).not_to have_received(:close)
    end

    it "returns the navigated tab" do
      expect(runner.run_diagnose).to eq(tab)
    end

    it "waits for the window to be loaded when requested" do
      runner(wait_window_loaded: true).run_diagnose

      expect(tab).to have_received(:wait_until_page_loaded)
    end
  end

  describe "#close_all" do
    it "closes the tab, window and user context that #run_diagnose opened" do
      instance = runner
      instance.run_diagnose

      instance.close_all

      expect([tab, window, user_context]).to all(have_received(:close))
    end
  end
end
