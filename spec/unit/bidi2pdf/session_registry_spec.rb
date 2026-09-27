# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::SessionRegistry do
  subject(:registry) { described_class.new("http://remote-chrome:3000/session", dir: dir) }

  let(:dir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(dir) }

  it "remembers a recorded session with the time it was opened" do
    registry.record("abc", created_at: 100)

    expect(registry.recorded_before(100)).to eq(["abc"])
  end

  it "does not count a session opened after the cutoff" do
    registry.record("abc", created_at: 200)

    expect(registry.recorded_before(100)).to be_empty
  end

  it "forgets a session" do
    registry.record("abc", created_at: 100)
    registry.forget("abc")

    expect(registry.recorded_before(1_000)).to be_empty
  end

  it "is shared by every registry for the same chromedriver in the same directory" do
    registry.record("abc", created_at: 100)

    expect(described_class.new("http://remote-chrome:3000/session", dir: dir).recorded_before(100)).to eq(["abc"])
  end

  it "keeps one file per chromedriver" do
    registry.record("abc", created_at: 100)

    expect(described_class.new("http://other-chrome:3000/session", dir: dir).recorded_before(100)).to be_empty
  end

  it "creates its file readable by its owner only" do
    registry.record("abc")

    expect(File.stat(registry.path).mode & 0o777).to eq(0o600)
  end

  it "treats a corrupt file as empty" do
    File.write(registry.path, "{not json")

    expect(registry.recorded_before(Time.now.to_i)).to be_empty
  end

  context "when the directory is not writable" do
    subject(:registry) { described_class.new("http://remote-chrome:3000/session", dir: File.join(dir, "missing")) }

    it "does not raise, it reports that recording failed" do
      expect(registry.record("abc")).to be(false)
    end

    it "warns once and tells its subscribers" do
      events = []
      allow(Bidi2pdf.notification_service).to receive(:instrument).and_wrap_original do |original, name, payload = {}, &block|
        events << name
        original.call(name, payload, &block)
      end

      2.times { registry.record("abc") }

      expect(events.count("session_warmer.registry_unavailable.bidi2pdf")).to eq(1)
    end
  end
end
