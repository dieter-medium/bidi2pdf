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

  describe "leases" do
    let(:heartbeat) { Bidi2pdf::SessionRegistry::Heartbeat }

    after { heartbeat.held_ids(registry).each { |id| registry.release(id) } }

    it "counts a session this process holds as live" do
      registry.hold("abc")

      expect(registry.leased).to eq(["abc"])
    end

    it "counts a session whose lease ran out as not live" do
      registry.record("abc", created_at: 100)

      expect(registry.leased(now: 1_000, ttl: 60)).to be_empty
    end

    it "keeps the lease of a held session fresh with every heartbeat" do
      registry.hold("abc")
      later = Time.now.to_i + 600

      heartbeat.beat!(now: later)

      expect(registry.leased(now: later, ttl: 60)).to eq(["abc"])
    end

    it "stops renewing a released session but keeps its entry for a sweeper" do
      registry.hold("abc")
      registry.release("abc")
      later = Time.now.to_i + 600

      heartbeat.beat!(now: later)

      expect([registry.leased(now: later, ttl: 60), registry.recorded.keys]).to eq([[], ["abc"]])
    end

    it "stops holding a forgotten session" do
      registry.hold("abc")
      registry.forget("abc")

      expect(heartbeat.held_ids(registry)).to be_empty
    end

    it "reads a file of the first format, without leases" do
      File.write(registry.path, JSON.generate("abc" => 100))

      expect([registry.recorded, registry.leased(now: 100)]).to eq([{ "abc" => 100 }, []])
    end

    it "holds nothing in a forked child - the parent's sessions are the parent's to renew" do
      registry.hold("abc")

      pid = fork { exit!(heartbeat.held_ids(registry).empty? ? 0 : 1) }
      Process.wait(pid)

      expect(Process.last_status.exitstatus).to eq(0)
    end
  end
end
