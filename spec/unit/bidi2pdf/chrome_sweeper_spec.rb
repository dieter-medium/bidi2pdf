# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::ChromeSweeper do
  let(:chromedriver) { FakeChromedriver.new }
  let(:inspector) { FakeSessionInspector.build(time: time) }

  let(:session_url) { "http://remote-chrome:3000/session" }
  let(:dir) { Dir.mktmpdir }
  let(:registry) { Bidi2pdf::SessionRegistry.new(session_url, dir: dir) }
  let(:time) { [1_000.0] }

  after { FileUtils.rm_rf(dir) }

  def sweeper(**)
    described_class.new(session_url, registry: registry, api: chromedriver.api(session_url),
                                     inspector: inspector, clock: -> { time.first }, **)
  end

  def running(ages)
    chromedriver.sessions.concat(ages.keys)
    inspector.ages.merge!(ages)
  end

  describe "scope" do
    it "looks only at recorded sessions by default" do
      running("mine" => 900, "foreign" => 900)
      registry.record("mine", created_at: 100)

      sweeper.sweep!

      expect(chromedriver.sessions).to eq(["foreign"])
    end

    it "looks at every session on the chromedriver with scope :all" do
      running("a" => 900, "b" => 900)

      sweeper(scope: :all).sweep!

      expect(chromedriver.sessions).to be_empty
    end

    it "forgets recorded sessions chromedriver no longer has" do
      registry.record("gone", created_at: 100)

      sweeper.sweep!

      expect(registry.recorded).to be_empty
    end
  end

  describe "orphan age" do
    it "closes sessions older than orphan_age" do
      running("old" => 700, "fresh" => 300)

      sweeper(scope: :all, orphan_age: 600).sweep!

      expect(chromedriver.sessions).to eq(["fresh"])
    end

    it "ages a recorded session by its registry time" do
      running("recorded" => nil)
      registry.record("recorded", created_at: 100)

      result = sweeper(orphan_age: 600).sweep!

      expect(result.closed.map(&:to_h)).to eq([{ id: "recorded", age: 900, why: :orphan }])
    end

    it "never closes a session younger than min_age" do
      running("young" => 30)

      sweeper(scope: :all, orphan_age: 10, min_age: 60).sweep!

      expect(chromedriver.sessions).to eq(["young"])
    end

    it "never closes the caller's own sessions" do
      running("own" => 9_999)

      sweeper(scope: :all, own_sessions: -> { ["own"] }).sweep!

      expect(chromedriver.sessions).to eq(["own"])
    end

    it "drops a closed session from the registry" do
      running("old" => nil)
      registry.record("old", created_at: 100)

      sweeper.sweep!

      expect(registry.recorded).to be_empty
    end
  end

  describe "unresponsive sessions" do
    it "keeps a session that failed fewer checks than unresponsive_checks" do
      running("hung" => 100)
      inspector.hung << "hung"

      sweeper(scope: :all, unresponsive_checks: 2).sweep!

      expect(chromedriver.sessions).to eq(["hung"])
    end

    it "closes a session after unresponsive_checks failed checks in a row" do
      running("hung" => 100)
      inspector.hung << "hung"
      service = sweeper(scope: :all, unresponsive_checks: 2)

      service.sweep!
      service.sweep!

      expect(chromedriver.sessions).to be_empty
    end

    it "starts counting again after a check that passed" do
      running("flaky" => 100)
      service = sweeper(scope: :all, unresponsive_checks: 2)
      inspector.hung << "flaky"
      service.sweep!
      inspector.hung.clear
      service.sweep!
      inspector.hung << "flaky"

      service.sweep!

      expect(chromedriver.sessions).to eq(["flaky"])
    end

    it "counts a renderer burning CPU the whole time between two sweeps as a failed check" do
      running("loop" => 100)
      service = sweeper(scope: :all, unresponsive_checks: 2)
      [0.0, 29.5, 59.0].each_with_index do |cpu, index|
        time[0] = 1_000.0 + (index * 30)
        inspector.cpu["loop"] = { 42 => cpu }
        service.sweep!
      end

      expect(chromedriver.sessions).to be_empty
    end

    it "closes a hung session in one one-shot sweep given a check_interval" do
      running("hung" => 100)
      inspector.hung << "hung"

      sweeper(scope: :all).sweep!(check_interval: 0.01)

      expect(chromedriver.sessions).to be_empty
    end

    it "counts the checks of #observe" do
      running("hung" => 100)
      inspector.hung << "hung"
      service = sweeper(scope: :all)

      service.observe
      service.sweep!

      expect(chromedriver.sessions).to be_empty
    end

    it "starts counting afresh for a session that went away and came back" do
      running("hung" => 100)
      inspector.hung << "hung"
      service = sweeper(scope: :all)
      service.sweep!
      chromedriver.sessions.clear
      service.sweep!
      chromedriver.sessions << "hung"

      service.sweep!

      expect(chromedriver.sessions).to eq(["hung"])
    end

    it "rejects a check_interval that is not a positive number" do
      expect { sweeper.sweep!(check_interval: -1) }.to raise_error(Bidi2pdf::InvalidConfigError, /check_interval/)
    end

    it "reports an unresponsive session before closing it" do
      running("hung" => 100)
      inspector.hung << "hung"

      expect(sweeper(scope: :all).sweep!.unresponsive).to eq(["hung"])
    end
  end

  describe "session limit" do
    it "closes the oldest sessions down to max_sessions" do
      running("oldest" => 500, "middle" => 400, "newest" => 300)

      sweeper(scope: :all, max_sessions: 1).sweep!

      expect(chromedriver.sessions).to eq(["newest"])
    end

    it "counts sessions outside the scope towards the limit without closing them" do
      running("foreign" => 500, "mine" => 300)
      registry.record("mine", created_at: 700)

      sweeper(max_sessions: 1).sweep!

      expect(chromedriver.sessions).to eq(["foreign"])
    end

    it "reports the limit as exceeded when only young sessions are left" do
      running("young" => 10, "younger" => 5)

      expect(sweeper(scope: :all, max_sessions: 1).sweep!.limit_exceeded).to be(true)
    end

    it "derives the limit from the pids limit with :auto" do
      expect(sweeper(max_sessions: :auto, pids_limit: 1024).limit).to eq(7)
    end

    it "has no limit with :auto but no pids limit" do
      expect(sweeper(max_sessions: :auto).limit).to be_nil
    end
  end

  describe "sessions of a live process" do
    # Recorded long ago, but its process renewed the lease 10 s before "now".
    def held_by_a_live_process(id)
      registry.record(id, created_at: 100)
      registry.renew([id], at: time.first.to_i - 10)
    end

    it "never closes a session whose lease is fresh" do
      running("held" => nil)
      held_by_a_live_process("held")

      sweeper(max_sessions: 1, lease_ttl: 60).sweep!(pressure: true)

      expect(chromedriver.sessions).to eq(["held"])
    end

    it "closes it once the lease ran out" do
      running("held" => nil)
      held_by_a_live_process("held")
      time[0] += 120

      sweeper(lease_ttl: 60).sweep!

      expect(chromedriver.sessions).to be_empty
    end

    it "reports the limit as exceeded when only live sessions are over it" do
      running("a" => nil, "b" => nil)
      held_by_a_live_process("a")
      held_by_a_live_process("b")

      expect(sweeper(max_sessions: 1).sweep!.limit_exceeded).to be(true)
    end

    it "lists it as live" do
      running("held" => nil)
      held_by_a_live_process("held")

      expect(sweeper.sessions.map(&:live)).to eq([true])
    end
  end

  describe "pressure" do
    it "closes every session nobody holds that is past min_age" do
      running("idle" => 100)

      result = sweeper(scope: :all).sweep!(pressure: true)

      expect(result.closed.map(&:to_h)).to eq([{ id: "idle", age: 100, why: :pressure }])
    end

    it "still leaves a session younger than min_age alone" do
      running("young" => 10)

      sweeper(scope: :all).sweep!(pressure: true)

      expect(chromedriver.sessions).to eq(["young"])
    end
  end

  describe "retrying a failed render" do
    def failing_once(error)
      attempts = 0
      lambda do
        attempts += 1
        raise error if attempts == 1

        :rendered
      end
    end

    it "returns the second attempt's result after a resource error" do
      render = failing_once(Bidi2pdf::SessionNotStartedError.new("session not created"))

      expect(sweeper(scope: :all).with_retry { render.call }).to eq(:rendered)
    end

    it "sweeps under pressure before the second attempt" do
      running("idle" => 100)
      render = failing_once(Bidi2pdf::CmdTimeoutError.new("timeout"))

      sweeper(scope: :all).with_retry { render.call }

      expect(chromedriver.sessions).to be_empty
    end

    it "does not retry an error the page caused" do
      error = Bidi2pdf::CmdError.new(Bidi2pdf::Bidi::Commands::BrowsingContextGetTree.new, { "error" => "invalid argument" })

      expect { sweeper.with_retry { raise error } }.to raise_error(Bidi2pdf::CmdError)
    end

    it "lets a second failure through" do
      expect { sweeper.with_retry { raise Bidi2pdf::SessionNotStartedError, "still full" } }
        .to raise_error(Bidi2pdf::SessionNotStartedError, "still full")
    end

    it "retries on the error classes it is given" do
      render = failing_once(IOError.new("disk full"))

      expect(sweeper.with_retry(retry_on: [IOError]) { render.call }).to eq(:rendered)
    end
  end

  describe "observing" do
    it "closes nothing" do
      running("old" => 900)

      sweeper(scope: :all).observe

      expect(chromedriver.sessions).to eq(["old"])
    end
  end

  describe "dry run" do
    it "closes nothing" do
      running("old" => 900)

      sweeper(scope: :all, dry_run: true).sweep!

      expect(chromedriver.sessions).to eq(["old"])
    end

    it "reports what it would close" do
      running("old" => 900)

      expect(sweeper(scope: :all, dry_run: true).sweep!.closed.map(&:id)).to eq(["old"])
    end
  end

  describe "failures" do
    it "reports a session chromedriver refused to close" do
      running("stuck" => 900)
      chromedriver.failing << "stuck"

      expect(sweeper(scope: :all).sweep!.errors).to eq(["closing stuck failed"])
    end

    it "never raises when chromedriver cannot be reached" do
      broken = Bidi2pdf::ChromedriverApi.new(session_url, http: ->(*) { raise Errno::ECONNREFUSED })
      service = described_class.new(session_url, registry: registry, api: broken, inspector: inspector)

      expect(service.sweep!.errors).to eq(["Connection refused"])
    end

    it "skips a sweep while another process holds the sweep lock" do
      File.open("#{registry.path}.lock", File::RDWR | File::CREAT, 0o600) do |lock|
        lock.flock(File::LOCK_EX)

        expect(Thread.new { sweeper.sweep!.skipped }.value).to be(true)
      end
    end

    it "rejects an unknown scope" do
      expect { sweeper(scope: :everything) }.to raise_error(Bidi2pdf::InvalidConfigError, /scope/)
    end

    it "rejects a max_sessions that is not a positive Integer" do
      expect { sweeper(max_sessions: 0) }.to raise_error(Bidi2pdf::InvalidConfigError, /max_sessions/)
    end
  end

  describe "periodic sweeps" do
    it "sweeps in the background until stopped" do
      running("old" => 900)
      service = sweeper(scope: :all, interval: 0.01).start

      Timeout.timeout(2) { sleep 0.01 until chromedriver.sessions.empty? }
      service.stop

      expect(chromedriver.sessions).to be_empty
    end

    it "needs an interval to start" do
      expect { sweeper.start }.to raise_error(Bidi2pdf::InvalidConfigError, /interval/)
    end
  end

  it "sweeps once through the class method" do
    running("old" => 900)

    described_class.sweep!(session_url, scope: :all, registry: registry, api: chromedriver.api(session_url),
                                        inspector: inspector)

    expect(chromedriver.sessions).to be_empty
  end
end
