# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::Launcher do
  let(:manager) { instance_double(Bidi2pdf::ChromedriverManager, start: nil, stop: nil, session: session) }
  let(:session) { instance_double(Bidi2pdf::Bidi::Session) }
  let(:tab) { instance_double(Bidi2pdf::Bidi::BrowserTab) }
  let(:runner) { instance_double(Bidi2pdf::SessionRunner, run: "pdf-base64", run_diagnose: tab, close_all: nil) }

  before do
    allow(Bidi2pdf::ChromedriverManager).to receive(:new).and_return(manager)
    allow(Bidi2pdf::SessionRunner).to receive(:new).and_return(runner)
  end

  def launcher(**overrides)
    described_class.new(url: "https://example.com", inputfile: nil, output: "out.pdf", cookies: {}, headers: {}, auth: {}, **overrides)
  end

  describe "#launch" do
    it "runs the session via SessionRunner#run" do
      launcher.launch

      expect(runner).to have_received(:run)
    end
  end

  describe "#diagnose" do
    it "returns the navigated tab from SessionRunner#run_diagnose" do
      expect(launcher.diagnose).to eq(tab)
    end

    it "does not itself call SessionRunner#run" do
      launcher.diagnose

      expect(runner).not_to have_received(:run)
    end
  end

  describe "#stop" do
    it "stops the chromedriver manager" do
      instance = launcher
      instance.launch

      instance.stop

      expect(manager).to have_received(:stop)
    end

    it "closes what #diagnose opened" do
      instance = launcher
      instance.diagnose

      instance.stop

      expect(runner).to have_received(:close_all)
    end

    it "is a no-op close_all when only #launch (never #diagnose) was called" do
      instance = launcher
      instance.launch

      instance.stop

      expect(runner).not_to have_received(:close_all)
    end
  end
end
