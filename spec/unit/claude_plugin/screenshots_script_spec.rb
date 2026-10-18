# frozen_string_literal: true

require "spec_helper"

# The page-screenshots skill's script (claude-plugin/skills/page-screenshots/scripts/screenshots.rb):
# its file names and its cleanup, without a browser. The real run is the integration spec of the
# same name.
require File.expand_path("../../../claude-plugin/skills/page-screenshots/scripts/screenshots.rb", __dir__)

RSpec.describe Screenshots do
  describe ".path_for" do
    def path(page) = described_class.path_for(page, 360, "light")

    it "names the start page index" do
      expect(path("/")).to eq("index-360-light.png")
    end

    it "keeps a plain page's name" do
      expect(path("/about")).to eq("about-360-light.png")
    end

    it "keeps the page's folders, so /account/settings and /account-settings stay apart" do
      expect([path("/account/settings"), path("/account-settings")]).to eq(%w[account/settings-360-light.png account-settings-360-light.png])
    end

    it "names a folder's own page index" do
      expect(path("/docs/")).to eq("docs/index-360-light.png")
    end

    it "keeps two pages apart whose names only differ in characters a file name cannot carry" do
      expect(path("/a.b")).not_to eq(path("/a-b"))
    end

    it "keeps a page with a query apart from the page without one" do
      expect(path("/search?q=1")).not_to eq(path("/search"))
    end

    it "names a changed page by its hash, so the name is the same on every run" do
      expect(path("/a.b")).to eq("a-b-#{Digest::SHA256.hexdigest("/a.b")[0, 8]}-360-light.png")
    end

    it "never leaves the output folder" do
      expect(path("/../../etc/passwd").split("/")).not_to include("..", ".")
    end
  end

  describe ".with_browser" do
    def failing_session(**methods)
      instance_double(Bidi2pdf::Bidi::Session, close: nil, **methods).tap do |session|
        allow(session).to receive(:start).and_raise(Bidi2pdf::SessionNotStartedError, "no Chrome") unless methods.key?(:start)
      end
    end

    def local_manager(session)
      instance_double(Bidi2pdf::ChromedriverManager, start: nil, stop: nil, session: session).tap do |manager|
        allow(Bidi2pdf::ChromedriverManager).to receive(:new).and_return(manager)
      end
    end

    def swallow(error_class)
      yield
    rescue error_class
      nil
    end

    it "passes on why the session did not start" do
      local_manager(failing_session)

      expect { described_class.with_browser(nil) { nil } }.to raise_error(Bidi2pdf::SessionNotStartedError)
    end

    it "stops a local chromedriver whose session failed to start" do
      manager = local_manager(failing_session)

      swallow(Bidi2pdf::SessionNotStartedError) { described_class.with_browser(nil) { nil } }

      expect(manager).to have_received(:stop)
    end

    it "closes a remote session whose start failed" do
      session = failing_session
      allow(Bidi2pdf::Bidi::Session).to receive(:new).and_return(session)

      swallow(Bidi2pdf::SessionNotStartedError) { described_class.with_browser("http://remote-chrome:3000/session") { nil } }

      expect(session).to have_received(:close)
    end

    it "stops the local chromedriver even when closing the session fails" do
      session = failing_session(start: nil)
      allow(session).to receive(:close).and_raise(Bidi2pdf::WebsocketError, "gone")
      manager = local_manager(session)

      swallow(Bidi2pdf::WebsocketError) { described_class.with_browser(nil) { nil } }

      expect(manager).to have_received(:stop)
    end
  end
end
