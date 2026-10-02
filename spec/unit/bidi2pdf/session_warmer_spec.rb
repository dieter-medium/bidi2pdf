# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::SessionWarmer do
  subject(:warmer) { described_class.new(config, slot_factory: -> { slot }) }

  let(:tab) { instance_double(Bidi2pdf::Bidi::BrowserTab, close: nil) }
  let(:window) { instance_double(Bidi2pdf::Bidi::BrowserTab, create_browser_tab: tab, close: nil) }
  let(:user_context) { instance_double(Bidi2pdf::Bidi::UserContext, create_browser_window: window, close: nil) }
  let(:browser) { instance_double(Bidi2pdf::Bidi::Browser, create_user_context: user_context) }
  let(:client) { instance_double(Bidi2pdf::Bidi::Client, open?: true) }
  let(:session) { instance_double(Bidi2pdf::Bidi::Session, started?: true, close: nil, client: client) }
  let(:manager) { instance_double(Bidi2pdf::ChromedriverManager, stop: nil) }
  let(:slot) { { session: session, browser: browser, manager: manager } }

  let(:config) { described_class::Configuration.new.tap { |c| c.size = 1 } }

  # Polls a real background thread's effect without a fixed sleep - fails loudly instead of hanging
  # forever if the condition never becomes true.
  def eventually(timeout: 2)
    deadline = Time.now + timeout
    loop do
      result = yield
      return result if result
      raise "condition not met within #{timeout}s" if Time.now > deadline

      sleep 0.01
    end
  end

  describe "Configuration" do
    subject(:cfg) { described_class::Configuration.new }

    it "rejects sweeper settings that are not a Hash" do
      cfg.sweeper = true

      expect { cfg.validate! }.to raise_error(ArgumentError, /sweeper/)
    end

    it "defaults size to 1" do
      expect(cfg.size).to eq(1)
    end

    it "defaults headless to true" do
      expect(cfg.headless).to be(true)
    end

    it "defaults chrome_args to DEFAULT_CHROME_ARGS" do
      expect(cfg.chrome_args).to eq(Bidi2pdf::Bidi::Session::DEFAULT_CHROME_ARGS)
    end

    it "defaults remote_browser_url to nil" do
      expect(cfg.remote_browser_url).to be_nil
    end

    it "defaults slot_factory to nil" do
      expect(cfg.slot_factory).to be_nil
    end

    it "bounds idle time by default rather than leaving warm slots open indefinitely" do
      expect(cfg.max_idle_age).to eq(300)
    end

    it "bounds shutdown by default rather than waiting on a Chrome that never answers" do
      expect(cfg.shutdown_timeout).to eq(10)
    end

    describe "#validate!" do
      it "accepts the defaults" do
        expect { cfg.validate! }.not_to raise_error
      end

      it "accepts nil shutdown_timeout (waits for ever)" do
        cfg.shutdown_timeout = nil

        expect { cfg.validate! }.not_to raise_error
      end

      [0, -1, "10"].each do |bad|
        it "rejects shutdown_timeout #{bad.inspect}" do
          cfg.shutdown_timeout = bad

          expect { cfg.validate! }.to raise_error(ArgumentError, /shutdown_timeout/)
        end
      end

      it "accepts nil max_idle_age (limit disabled)" do
        cfg.max_idle_age = nil

        expect { cfg.validate! }.not_to raise_error
      end

      [0, -5, "300"].each do |bad|
        it "rejects max_idle_age #{bad.inspect}" do
          cfg.max_idle_age = bad

          expect { cfg.validate! }.to raise_error(ArgumentError, /max_idle_age/)
        end
      end

      [-1, 1.5, "2"].each do |bad|
        it "rejects size #{bad.inspect}" do
          cfg.size = bad

          expect { cfg.validate! }.to raise_error(ArgumentError, /size/)
        end
      end

      [0, -1, "600", :never].each do |bad|
        it "rejects orphan_age #{bad.inspect}" do
          cfg.orphan_age = bad

          expect { cfg.validate! }.to raise_error(ArgumentError, /orphan_age/)
        end
      end
    end

    describe "#effective_orphan_age" do
      it "is twice max_idle_age by default, beyond any live warmer's own recycling" do
        expect(cfg.effective_orphan_age).to eq(600)
      end

      it "is off when there is no max_idle_age to derive it from" do
        cfg.max_idle_age = nil

        expect(cfg.effective_orphan_age).to be_nil
      end

      it "follows an explicit value" do
        cfg.orphan_age = 42

        expect(cfg.effective_orphan_age).to eq(42)
      end
    end
  end

  describe ".default_slot_factory" do
    context "when remote_browser_url is not set" do
      before do
        allow(session).to receive(:browser).and_return(browser)
        allow(Bidi2pdf::ChromedriverManager).to receive(:new).and_return(manager)
        allow(manager).to receive_messages(start: nil, session: session)
      end

      it "starts a ChromedriverManager" do
        described_class.default_slot_factory(config).call

        expect(manager).to have_received(:start)
      end

      it "builds the slot from the manager's session and browser" do
        built = described_class.default_slot_factory(config).call

        expect(built).to eq(session: session, browser: browser, manager: manager)
      end
    end

    context "when remote_browser_url is set" do
      before do
        config.remote_browser_url = "http://remote-chrome:9515/session"
        allow(session).to receive(:browser).and_return(browser)
        allow(Bidi2pdf::Bidi::Session).to receive(:new)
                                            .with(hash_including(session_url: config.remote_browser_url))
                                            .and_return(session)
        allow(Bidi2pdf::ChromedriverManager).to receive(:new)
      end

      it "does not spawn a ChromedriverManager" do
        described_class.default_slot_factory(config).call

        expect(Bidi2pdf::ChromedriverManager).not_to have_received(:new)
      end

      it "builds the slot directly from the remote session, with no manager" do
        built = described_class.default_slot_factory(config).call

        expect(built).to eq(session: session, browser: browser, manager: nil)
      end
    end

    # Regression: a failure after chromedriver was up (or the session had started) used to strand
    # it - the factory never returned a slot, so no caller had anything to retire.
    def build_and_swallow
      described_class.default_slot_factory(config).call
    rescue RuntimeError
      nil
    end

    context "when building a local slot fails part-way" do
      before do
        allow(session).to receive(:browser).and_raise("browser never came up")
        allow(Bidi2pdf::ChromedriverManager).to receive(:new).and_return(manager)
        allow(manager).to receive_messages(start: nil, session: session)
      end

      it "still propagates the error" do
        expect { described_class.default_slot_factory(config).call }.to raise_error("browser never came up")
      end

      it "stops the chromedriver it had already started" do
        build_and_swallow

        expect(manager).to have_received(:stop)
      end

      it "closes the partially started session" do
        build_and_swallow

        expect(session).to have_received(:close)
      end
    end

    context "when building a remote slot fails part-way" do
      before do
        config.remote_browser_url = "http://remote-chrome:9515/session"
        allow(session).to receive(:browser).and_raise("browser never came up")
        allow(Bidi2pdf::Bidi::Session).to receive(:new).and_return(session)
      end

      it "closes the partially started session" do
        build_and_swallow

        expect(session).to have_received(:close)
      end
    end
  end

  describe "pre-warming at construction" do
    # Regression: if slot N failed, `new` raised and slots 1..N-1 were live Chromes nobody owned.
    context "when a later slot fails" do
      let(:config) { described_class::Configuration.new.tap { |c| c.size = 2 } }
      let(:failing_second_factory) do
        calls = 0
        lambda do
          calls += 1
          raise "chrome is down" if calls == 2

          slot
        end
      end

      def construct_and_swallow
        described_class.new(config, slot_factory: failing_second_factory)
      rescue RuntimeError
        nil
      end

      it "still fails fast" do
        expect { described_class.new(config, slot_factory: failing_second_factory) }.to raise_error("chrome is down")
      end

      it "retires the slots it had already created" do
        construct_and_swallow

        expect(manager).to have_received(:stop)
      end
    end
  end

  describe "class-level singleton API" do
    # .configure now eagerly instantiates (see the "eagerly pre-warms" example below), so every
    # call here needs a stub slot_factory - otherwise it would spawn real Chrome via
    # default_slot_factory, which this fast unit tier must never do. .shutdown right after resets
    # @instance to nil so it doesn't linger holding this example's doubles into the next example's
    # own reset, where rspec-mocks would reject them as leaked.
    after do
      described_class.configure { |c| c.slot_factory = -> { slot } }
      described_class.shutdown
    end

    describe ".config" do
      it "returns a Configuration instance" do
        expect(described_class.config).to be_a(described_class::Configuration)
      end
    end

    describe ".configure" do
      it "yields a Configuration object to the block" do
        yielded = nil
        described_class.configure do |c|
          c.slot_factory = -> { slot }
          yielded = c
        end

        expect(yielded).to be_a(described_class::Configuration)
      end

      it "stores configuration so .config reflects new values" do
        described_class.configure do |c|
          c.size = 3
          c.slot_factory = -> { slot }
        end

        expect(described_class.config.size).to eq(3)
      end

      it "eagerly pre-warms config.size slots, rather than lazily on the first request" do
        calls = 0
        mutex = Mutex.new
        described_class.configure do |c|
          c.size = 2
          c.slot_factory = lambda {
            mutex.synchronize { calls += 1 }
            slot
          }
        end

        expect(mutex.synchronize { calls }).to eq(2)
      end

      # Regression: a failed construction used to leave the previous, already-shut-down instance
      # registered - still serving cold slots, but never warming again.
      it "does not keep a stale, shut-down instance registered when construction fails" do
        described_class.configure { |c| c.slot_factory = -> { slot } }

        begin
          described_class.configure { |c| c.slot_factory = -> { raise "chrome is down" } }
        rescue RuntimeError
          nil
        end

        expect(described_class.instance_variable_get(:@instance)).to be_nil
      end
    end

    describe ".with_tab" do
      it "yields a tab built from the configured slot_factory" do
        described_class.configure do |c|
          c.size = 1
          c.slot_factory = -> { slot }
        end

        yielded_tab = nil
        described_class.with_tab { |t| yielded_tab = t }

        expect(yielded_tab).to eq(tab)
      end
    end

    describe ".shutdown" do
      it "allows a tab to be yielded from a fresh warmer afterwards" do
        described_class.configure do |c|
          c.size = 1
          c.slot_factory = -> { slot }
        end
        described_class.with_tab { |t| t }

        described_class.shutdown

        yielded = nil
        described_class.with_tab { |t| yielded = t }

        expect(yielded).to eq(tab)
      end
    end
  end

  describe "#with_tab" do
    after { warmer.shutdown }

    it "yields a browser tab to the block" do
      yielded = nil
      warmer.with_tab { |t| yielded = t }

      expect(yielded).to eq(tab)
    end

    it "closes the tab after the block completes" do
      warmer.with_tab { |t| t }

      expect(tab).to have_received(:close)
    end

    it "closes the window after the block completes" do
      warmer.with_tab { |t| t }

      expect(window).to have_received(:close)
    end

    it "closes the user context after the block completes" do
      warmer.with_tab { |t| t }

      expect(user_context).to have_received(:close)
    end

    it "retires the slot (stops the manager) after the block completes, rather than reusing it" do
      warmer.with_tab { |t| t }

      expect(manager).to have_received(:stop)
    end

    it "still succeeds on a second consecutive call" do
      warmer.with_tab { |t| t }

      expect { warmer.with_tab { |t| t } }.not_to raise_error
    end

    context "when the block raises" do
      def with_tab_raising_boom
        warmer.with_tab { raise "boom" }
      rescue RuntimeError
        nil
      end

      it "propagates the exception" do
        expect { warmer.with_tab { raise "boom" } }.to raise_error("boom")
      end

      it "still closes the tab" do
        with_tab_raising_boom

        expect(tab).to have_received(:close)
      end

      it "still retires the slot" do
        with_tab_raising_boom

        expect(manager).to have_received(:stop)
      end
    end

    context "when a pre-warmed slot never started" do
      before { allow(session).to receive(:started?).and_return(false) }

      it "discards it and falls back to a fresh slot from the factory" do
        yielded = nil
        warmer.with_tab { |t| yielded = t }

        expect(yielded).to eq(tab)
      end

      it "still stops the dead slot's manager" do
        warmer.with_tab { |t| t }

        # Both the discarded dead spare and the fresh cold-fallback slot share this same double
        # (the test factory always returns the same doubles), so :stop legitimately fires twice.
        expect(manager).to have_received(:stop).at_least(:once)
      end
    end

    context "when a pre-warmed slot started fine but died externally while idle" do
      # Session#started? alone can't see this - it's just an internal flag, never updated by an
      # external death. The client's own #open? is what actually notices (see #healthy?).
      before { allow(client).to receive(:open?).and_return(false) }

      it "does not hand out the stale slot - falls back to a fresh one from the factory" do
        yielded = nil
        warmer.with_tab { |t| yielded = t }

        expect(yielded).to eq(tab)
      end

      it "still stops the stale slot's manager" do
        warmer.with_tab { |t| t }

        expect(manager).to have_received(:stop).at_least(:once)
      end
    end

    context "when the warm cache is empty" do
      let(:config) { described_class::Configuration.new.tap { |c| c.size = 0 } }

      it "falls back to a synchronous slot instead of blocking or raising" do
        yielded = nil
        warmer.with_tab { |t| yielded = t }

        expect(yielded).to eq(tab)
      end

      # Regression for a real bug: checkout used to call replenish_async unconditionally, even on a
      # miss that took nothing from @available - so a burst of misses each created one cold slot
      # *plus* one background spare, growing @available past config.size without bound.
      it "does not also warm a background spare for a miss - nothing was taken from the cache to replace" do
        calls = 0
        mutex = Mutex.new
        counted_factory = lambda do
          mutex.synchronize { calls += 1 }
          slot
        end
        warmer_empty = described_class.new(config, slot_factory: counted_factory)

        begin
          warmer_empty.with_tab { |t| t }
          sleep 0.2 # give a wrongly-triggered background replenishment a real chance to run

          expect(mutex.synchronize { calls }).to eq(1)
        ensure
          warmer_empty.shutdown
        end
      end
    end
  end

  describe "background replenishment" do
    it "warms a replacement slot after a checkout, off the request path" do
      mutex = Mutex.new
      calls = 0
      counted_factory = lambda do
        mutex.synchronize { calls += 1 }
        slot
      end
      warmer_with_counter = described_class.new(config, slot_factory: counted_factory)

      begin
        warmer_with_counter.with_tab { |t| t }

        expect(eventually { mutex.synchronize { calls } >= 2 }).to be(true)
      ensure
        warmer_with_counter.shutdown
      end
    end
  end

  describe "replenishing towards config.size" do
    # Counts factory calls and fails the ones whose (1-based) call number is listed in fail_on.
    def counting_factory(fail_on: [])
      mutex = Mutex.new
      calls = 0
      factory = lambda do
        number = mutex.synchronize { calls += 1 }
        raise "chrome is down" if fail_on.include?(number)

        slot
      end

      [factory, -> { mutex.synchronize { calls } }]
    end

    # Regression: replenishment used to fire only when a checkout popped a spare, so one failed warm
    # on a size-1 cache left it empty forever - every later checkout was a miss, and misses never
    # replenished.
    it "recovers after a failed replenishment instead of staying cold forever" do
      factory, calls = counting_factory(fail_on: [2])
      healing = described_class.new(config, slot_factory: factory)

      begin
        healing.with_tab { |t| t } # hit; its background warm (call 2) fails
        eventually { calls.call >= 2 }
        healing.with_tab { |t| t } # miss: cold slot (call 3) + a new warm attempt (call 4)

        expect(eventually { calls.call >= 4 }).to be(true)
      ensure
        healing.shutdown
      end
    end

    it "never holds more spares than config.size, however many checkouts ran" do
      factory, = counting_factory
      bounded = described_class.new(config, slot_factory: factory)

      begin
        5.times { bounded.with_tab { |t| t } }
        sleep 0.2 # let any over-eager warmer finish before looking

        expect(bounded.instance_variable_get(:@available).size).to be <= config.size
      ensure
        bounded.shutdown
      end
    end

    it "has nothing still warming once #shutdown returns" do
      factory, calls = counting_factory
      stopping = described_class.new(config, slot_factory: factory)
      stopping.with_tab { |t| t }
      stopping.shutdown
      calls_at_shutdown = calls.call
      sleep 0.2

      expect(calls.call).to eq(calls_at_shutdown)
    end
  end

  describe "max_idle_age" do
    def counting_factory
      mutex = Mutex.new
      calls = 0
      factory = lambda do
        mutex.synchronize { calls += 1 }
        slot
      end

      [factory, -> { mutex.synchronize { calls } }]
    end

    def warmer_with(max_idle_age:, factory:)
      aged = described_class::Configuration.new.tap do |c|
        c.size = 1
        c.max_idle_age = max_idle_age
      end

      described_class.new(aged, slot_factory: factory)
    end

    # The point of the setting: with no traffic at all, nothing but the reaper would ever look at
    # an idle slot.
    context "when a spare idles past it with no render ever arriving" do
      it "warms a replacement" do
        factory, calls = counting_factory
        idle = warmer_with(max_idle_age: 0.2, factory: factory)

        begin
          expect(eventually { calls.call >= 2 }).to be(true)
        ensure
          idle.shutdown
        end
      end

      it "retires the expired spare" do
        factory, = counting_factory
        stopped = Concurrent::AtomicBoolean.new(false)
        allow(manager).to receive(:stop) { stopped.make_true }
        idle = warmer_with(max_idle_age: 0.2, factory: factory)

        begin
          expect(eventually { stopped.true? }).to be(true)
        ensure
          idle.shutdown
        end
      end
    end

    # Reaper interval here is 250s, so only #checkout's own check can be what rejects the slot.
    it "never hands out a spare older than it, even before the reaper gets there" do
      factory, calls = counting_factory
      strict = warmer_with(max_idle_age: 1000, factory: factory)

      begin
        strict.instance_variable_get(:@available).first[:warmed_at] -= 2000
        strict.with_tab { |t| t }

        # initial + cold start + replenishment; a (wrong) warm hit would stop at 2.
        expect(eventually { calls.call >= 3 }).to be(true)
      ensure
        strict.shutdown
      end
    end

    it "runs no reaper when disabled" do
      factory, = counting_factory
      unlimited = warmer_with(max_idle_age: nil, factory: factory)

      begin
        expect(unlimited.instance_variable_get(:@reaper)).to be_nil
      ensure
        unlimited.shutdown
      end
    end

    it "stops the reaper on #shutdown" do
      factory, = counting_factory
      stopping = warmer_with(max_idle_age: 60, factory: factory)
      stopping.shutdown

      expect(stopping.instance_variable_get(:@reaper)).not_to be_alive
    end
  end

  describe "leftover sessions of processes that died uncleanly" do
    let(:dir) { Dir.mktmpdir }
    let(:session) { instance_double(Bidi2pdf::Bidi::Session, started?: true, close: nil, client: client, session_id: "mine") }
    let(:config) do
      described_class::Configuration.new.tap do |c|
        c.size = 1
        c.remote_browser_url = session_url
        c.registry_dir = dir
      end
    end

    def session_url = "http://remote-chrome:3000/session"
    def registry = Bidi2pdf::SessionRegistry.new(session_url, dir: dir)

    after do
      warmer.shutdown
      FileUtils.rm_rf(dir)
    end

    it "records every session it opens" do
      warmer

      expect(registry.recorded_before(Time.now.to_i + 1)).to eq(["mine"])
    end

    it "forgets a session once it closed it" do
      warmer.shutdown

      expect(registry.recorded_before(Time.now.to_i + 1)).to be_empty
    end

    context "with a spare still closing at the shutdown deadline" do
      def gate = @gate ||= Thread::Queue.new

      before { allow(session).to receive(:close) { gate.pop } }

      after { gate << :go }

      it "stops renewing its lease, so a sweeper can take the session" do
        warmer.shutdown(timeout: 0.1)

        expect(Bidi2pdf::SessionRegistry::Heartbeat.held_ids(registry)).not_to include("mine")
      end

      it "keeps its registry entry" do
        warmer.shutdown(timeout: 0.1)

        expect(registry.recorded_before(Time.now.to_i + 1)).to eq(["mine"])
      end
    end

    it "closes another process's leftover on start" do
      registry.record("dead-process", created_at: Time.now.to_i - 3_600)
      deleted = []
      allow(Bidi2pdf::SessionSweeper).to receive(:new).and_wrap_original do |original, url, reg|
        original.call(url, reg, http: lambda { |_method, url_to_delete|
          deleted << url_to_delete
          200
        })
      end

      warmer

      expect(deleted).to eq(["#{session_url}/dead-process"])
    end

    it "does not sweep when orphan_age is nil" do
      config.orphan_age = nil
      allow(Bidi2pdf::SessionSweeper).to receive(:new)

      warmer

      expect(Bidi2pdf::SessionSweeper).not_to have_received(:new)
    end

    it "leases its sessions even without an orphan age or a sweeper" do
      config.orphan_age = nil
      warmer

      expect(registry.leased).to eq(["mine"])
    end

    it "does not sweep or record in local mode - there is no shared chromedriver" do
      config.remote_browser_url = nil
      warmer

      expect(registry.recorded_before(Time.now.to_i + 1)).to be_empty
    end
  end

  describe "a ChromeSweeper on the remote chromedriver" do
    let(:dir) { Dir.mktmpdir }
    let(:session) { instance_double(Bidi2pdf::Bidi::Session, started?: true, close: nil, client: client, session_id: "mine") }
    let(:config) do
      described_class::Configuration.new.tap do |c|
        c.size = 1
        c.remote_browser_url = "http://remote-chrome:3000/session"
        c.registry_dir = dir
        c.sweeper = { scope: :all, api: chromedriver.api(c.remote_browser_url),
                      inspector: FakeSessionInspector.build({ "mine" => 9_999, "leaked" => 900 }) }
      end
    end

    # A method, not a let: the group already has as many memoized helpers as RuboCop allows.
    def chromedriver = @chromedriver ||= FakeChromedriver.new(%w[mine leaked])

    after do
      warmer.shutdown
      FileUtils.rm_rf(dir)
    end

    it "closes leaked sessions on demand" do
      warmer.sweep!

      expect(chromedriver.sessions).not_to include("leaked")
    end

    it "never closes its own sessions" do
      warmer.sweep!

      expect(chromedriver.sessions).to include("mine")
    end

    it "sweeps and tries once more when chromedriver refuses a new session" do
      chromedriver.sessions.delete("mine")
      attempts = 0
      refusing = described_class.new(config, slot_factory: lambda {
        attempts += 1
        raise Bidi2pdf::SessionNotStartedError, "session not created" if attempts == 1

        slot
      })
      refusing.shutdown

      expect([attempts, chromedriver.sessions]).to eq([2, []])
    end

    it "leaves a refused session to the caller with retry_refused_sessions off" do
      config.retry_refused_sessions = false
      refusing = -> { described_class.new(config, slot_factory: -> { raise Bidi2pdf::SessionNotStartedError, "session not created" }) }

      expect { refusing.call }.to raise_error(Bidi2pdf::SessionNotStartedError)
    end

    it "sweeps in the background with an interval" do
      config.sweeper[:interval] = 0.01
      warmer

      expect(eventually { !chromedriver.sessions.include?("leaked") }).to be(true)
    end

    it "sweeps through the configured singleton" do
      described_class.configure do |c|
        c.remote_browser_url = config.remote_browser_url
        c.registry_dir = dir
        c.sweeper = config.sweeper
        c.slot_factory = -> { slot }
      end

      described_class.sweep!
      described_class.shutdown

      expect(chromedriver.sessions).not_to include("leaked")
    end

    it "records its sessions for the sweeper even with the start-up sweep off" do
      config.orphan_age = nil
      warmer

      expect(Bidi2pdf::SessionRegistry.new(config.remote_browser_url, dir: dir).recorded.keys).to eq(["mine"])
    end

    it "keeps the start-up sweep off when orphan_age is nil" do
      config.orphan_age = nil
      allow(Bidi2pdf::SessionSweeper).to receive(:new)

      warmer

      expect(Bidi2pdf::SessionSweeper).not_to have_received(:new)
    end

    it "has nothing to sweep without a sweeper" do
      config.sweeper = nil

      expect(warmer.sweep!).to be_nil
    end
  end

  describe "#shutdown" do
    it "stops every currently-warm spare's manager" do
      warmer.shutdown

      expect(manager).to have_received(:stop)
    end

    it "still allows a subsequent with_tab to succeed via a fresh slot" do
      warmer.shutdown

      yielded = nil
      warmer.with_tab { |t| yielded = t }

      expect(yielded).to eq(tab)
    end

    it "reports nothing left running when everything finished in time" do
      expect(warmer.shutdown).to eq({})
    end

    it "rejects a timeout that is neither nil nor positive" do
      expect { warmer.shutdown(timeout: -1) }.to raise_error(ArgumentError, /timeout/)
    end

    it "closes a healthy spare even while a replenishment hangs" do
      gate = Thread::Queue.new
      calls = 0
      config.size = 2
      hanging = described_class.new(config, slot_factory: lambda {
        calls += 1
        gate.pop if calls == 3
        slot
      })
      hanging.with_tab { |t| t }
      allow(session).to receive(:close) { sleep 0.05 }

      expect(hanging.shutdown(timeout: 0.3)).to eq("replenishment" => 1)
    ensure
      gate << :go
    end

    it "closes a slow spare that finishes within the timeout" do
      allow(session).to receive(:close) { sleep 0.1 }
      warmer.shutdown(timeout: 2)

      expect(session).to have_received(:close)
    end

    context "with a spare whose Chrome no longer answers" do
      let(:gate) { Thread::Queue.new }

      before { allow(session).to receive(:close) { gate.pop } }

      after { gate << :go }

      it "stops waiting for it after the timeout" do
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        warmer.shutdown(timeout: 0.1)

        expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1
      end

      it "takes its timeout from the configuration" do
        config.shutdown_timeout = 0.1

        expect(warmer.shutdown).to eq("spare" => 1)
      end

      it "warns about what it left behind" do
        allow(Bidi2pdf.logger).to receive(:warn)
        warmer.shutdown(timeout: 0.1)

        expect(Bidi2pdf.logger).to have_received(:warn).with(/shutdown gave up after 0.1s, still running: 1 spare/)
      end

      it "reports what it left behind" do
        events = []
        subscriber = Bidi2pdf.notification_service.subscribe("session_warmer.shutdown_timeout.bidi2pdf") { |event| events << event.payload }
        warmer.shutdown(timeout: 0.1)

        expect(events).to eq([{ timeout: 0.1, pending: { "spare" => 1 } }])
      ensure
        Bidi2pdf.notification_service.unsubscribe("session_warmer.shutdown_timeout.bidi2pdf", subscriber)
      end
    end
  end
end
