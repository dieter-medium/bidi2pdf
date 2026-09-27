# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::SessionSweeper do
  subject(:sweeper) { described_class.new(session_url, registry, http: http) }

  let(:session_url) { "http://remote-chrome:3000/session" }
  let(:dir) { Dir.mktmpdir }
  let(:registry) { Bidi2pdf::SessionRegistry.new(session_url, dir: dir) }
  let(:deleted) { [] }
  let(:statuses) { Hash.new(200) }
  let(:http) do
    lambda do |method, url|
      deleted << url if method == :delete
      statuses[url]
    end
  end

  after { FileUtils.rm_rf(dir) }

  it "closes a recorded session older than the cutoff" do
    registry.record("old", created_at: 100)

    sweeper.sweep(older_than: 600, now: 1_000)

    expect(deleted).to eq(["#{session_url}/old"])
  end

  it "leaves a younger session alone - it may belong to a live process" do
    registry.record("young", created_at: 900)

    sweeper.sweep(older_than: 600, now: 1_000)

    expect(deleted).to be_empty
  end

  it "counts only sessions it actually closed" do
    registry.record("old", created_at: 100)
    registry.record("gone", created_at: 100)
    statuses["#{session_url}/gone"] = 404

    expect(sweeper.sweep(older_than: 600, now: 1_000)).to eq(1)
  end

  it "forgets a closed session, and one that was already gone" do
    registry.record("old", created_at: 100)
    registry.record("gone", created_at: 100)
    statuses["#{session_url}/gone"] = 404

    sweeper.sweep(older_than: 600, now: 1_000)

    expect(registry.recorded_before(1_000)).to be_empty
  end

  it "keeps a session chromedriver refused to close, so a later sweep tries again" do
    registry.record("stuck", created_at: 100)
    statuses["#{session_url}/stuck"] = 500

    sweeper.sweep(older_than: 600, now: 1_000)

    expect(registry.recorded_before(1_000)).to eq(["stuck"])
  end

  it "never raises when chromedriver cannot be reached" do
    registry.record("old", created_at: 100)
    unreachable = described_class.new(session_url, registry, http: ->(*) { raise Errno::ECONNREFUSED })

    expect(unreachable.sweep(older_than: 600, now: 1_000)).to eq(0)
  end
end
