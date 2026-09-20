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
  end
end
