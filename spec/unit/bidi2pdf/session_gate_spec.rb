# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::SessionGate do
  around do |example|
    limit = Bidi2pdf.session_start_concurrency
    timeout = Bidi2pdf.session_start_timeout
    gate = Bidi2pdf.session_gate
    described_class.reset!
    example.run
  ensure
    Bidi2pdf.session_start_concurrency = limit
    Bidi2pdf.session_start_timeout = timeout
    Bidi2pdf.session_gate = gate
    described_class.reset!
  end

  # A gate of one's own, e.g. a lock shared by several processes: counts its permits.
  def counting_gate
    Class.new do
      attr_reader :permits

      def initialize = @permits = 0

      def with_permit
        @permits += 1
        yield
      end
    end.new
  end

  # The most blocks that ran at the same time when +threads+ threads each took a permit for a short while.
  def peak_at_once(threads)
    running = Concurrent::AtomicFixnum.new
    peak = Concurrent::AtomicFixnum.new
    Array.new(threads) do
      Thread.new do
        described_class.with_permit do
          now = running.increment
          peak.update { |seen| [seen, now].max }
          sleep 0.05
          running.decrement
        end
      end
    end.each(&:join)
    peak.value
  end

  it "returns what the block returns" do
    expect(described_class.with_permit { :tab }).to eq(:tab)
  end

  it "lets no more setups run at once than the limit" do
    Bidi2pdf.session_start_concurrency = 2

    expect(peak_at_once(6)).to eq(2)
  end

  it "limits nothing when the limit is nil" do
    Bidi2pdf.session_start_concurrency = nil

    expect(peak_at_once(4)).to eq(4)
  end

  it "gives the permit back when the setup fails" do
    Bidi2pdf.session_start_concurrency = 1
    Bidi2pdf.session_start_timeout = 0.2
    begin
      described_class.with_permit { raise Bidi2pdf::SessionNotStartedError, "refused" }
    rescue Bidi2pdf::SessionNotStartedError
      nil
    end

    expect(described_class.with_permit { :next }).to eq(:next)
  end

  # Review of PR #184, finding 1: the notification ran between taking the permit and the ensure that returns it.
  it "keeps the permit free after a notification subscriber raised" do
    Bidi2pdf.session_start_concurrency = 1
    Bidi2pdf.session_start_timeout = 0.1
    subscriber = Bidi2pdf.notification_service.subscribe("session_gate.bidi2pdf") { raise "broken subscriber" }
    2.times do
      described_class.with_permit { nil }
    rescue Bidi2pdf::NotificationsError
      nil
    end
    Bidi2pdf.notification_service.unsubscribe("session_gate.bidi2pdf", subscriber)

    expect(described_class.with_permit { :free }).to eq(:free)
  ensure
    Bidi2pdf.notification_service.unsubscribe("session_gate.bidi2pdf", subscriber) if subscriber
  end

  # Review of PR #184, finding 2: a new limit built a new semaphore and the setups in flight stopped counting.
  describe "changing the limit while setups run" do
    def holding(count, seconds)
      holders = Array.new(count) { Thread.new { described_class.with_permit { sleep seconds } } }
      sleep 0.05
      yield
    ensure
      holders&.each(&:join)
    end

    it "makes a new setup wait while the setups in flight already reach the lower limit" do
      Bidi2pdf.session_start_concurrency = 2
      Bidi2pdf.session_start_timeout = 0.1

      holding(2, 0.4) do
        Bidi2pdf.session_start_concurrency = 1

        expect { described_class.with_permit { :third } }.to raise_error(Bidi2pdf::SessionStartTimeoutError)
      end
    end

    it "lets setups through again once the setups in flight are done" do
      Bidi2pdf.session_start_concurrency = 2
      Bidi2pdf.session_start_timeout = 0.1
      holding(2, 0.2) { Bidi2pdf.session_start_concurrency = 1 }
      Bidi2pdf.session_start_timeout = 2

      expect(peak_at_once(3)).to eq(1)
    end

    it "lets a setup through at once when the limit goes up" do
      Bidi2pdf.session_start_concurrency = 1
      Bidi2pdf.session_start_timeout = 0.1

      holding(1, 0.3) do
        Bidi2pdf.session_start_concurrency = 2

        expect(described_class.with_permit { :second }).to eq(:second)
      end
    end
  end

  it "raises SessionStartTimeoutError when no permit comes free in time" do
    Bidi2pdf.session_start_concurrency = 1
    Bidi2pdf.session_start_timeout = 0.1
    holder = Thread.new { described_class.with_permit { sleep 0.5 } }
    sleep 0.05

    expect { described_class.with_permit { :never } }.to raise_error(Bidi2pdf::SessionStartTimeoutError, /1 other session setup/)
  ensure
    holder&.join
  end

  it "reports the wait and whether a permit came" do
    events = []
    subscriber = Bidi2pdf.notification_service.subscribe("session_gate.bidi2pdf") { |event| events << event.payload }
    described_class.with_permit { nil }

    expect(events.map { |payload| payload.slice(:limit, :acquired) }).to eq([{ limit: Bidi2pdf.session_start_concurrency, acquired: true }])
  ensure
    Bidi2pdf.notification_service.unsubscribe("session_gate.bidi2pdf", subscriber) if subscriber
  end

  # The parent's threads hold every permit at the fork; they do not exist in the child, so the child must not
  # wait for them.
  it "gives a forked child a semaphore of its own", skip: (Process.respond_to?(:fork) ? false : "no fork here") do
    Bidi2pdf.session_start_concurrency = 1
    Bidi2pdf.session_start_timeout = 0.5
    reader, writer = IO.pipe
    holder = Thread.new { described_class.with_permit { sleep 1 } }
    sleep 0.1
    pid = fork do
      reader.close
      writer.write(described_class.with_permit { "got a permit" })
    rescue Bidi2pdf::SessionStartTimeoutError
      writer.write("timed out")
    ensure
      writer.close
      exit!(0)
    end
    writer.close
    Process.wait(pid)

    expect(reader.read).to eq("got a permit")
  ensure
    holder&.join
  end

  describe "a gate of one's own (Bidi2pdf.session_gate)" do
    it "hands the permit to it and returns what the block returns" do
      gate = counting_gate
      Bidi2pdf.session_gate = gate

      expect([described_class.with_permit { :tab }, gate.permits]).to eq([:tab, 1])
    end

    it "reports its wait, naming it" do
      events = []
      subscriber = Bidi2pdf.notification_service.subscribe("session_gate.bidi2pdf") { |event| events << event.payload }
      gate = counting_gate
      stub_const("FileLockGate", gate.class)
      Bidi2pdf.session_gate = gate
      described_class.with_permit { nil }

      expect(events.map { |payload| payload.slice(:acquired, :gate) }).to eq([{ acquired: true, gate: "FileLockGate" }])
    ensure
      Bidi2pdf.notification_service.unsubscribe("session_gate.bidi2pdf", subscriber) if subscriber
    end

    it "passes its timeout on to the caller" do
      gate = Object.new
      def gate.with_permit = raise(Bidi2pdf::SessionStartTimeoutError, "lock busy")
      Bidi2pdf.session_gate = gate

      expect { described_class.with_permit { :never } }.to raise_error(Bidi2pdf::SessionStartTimeoutError, "lock busy")
    end

    it "refuses an object that has no with_permit" do
      expect { Bidi2pdf.session_gate = Object.new }.to raise_error(Bidi2pdf::InvalidConfigError, /with_permit/)
    end
  end

  it "refuses a limit that is not a positive Integer" do
    expect { Bidi2pdf.session_start_concurrency = 0 }.to raise_error(Bidi2pdf::InvalidConfigError, /positive Integer/)
  end

  it "refuses a wait that is not a positive number" do
    expect { Bidi2pdf.session_start_timeout = -1 }.to raise_error(Bidi2pdf::InvalidConfigError, /positive number/)
  end

  it "starts with two setups at once" do
    expect(Bidi2pdf.session_start_concurrency).to eq(2)
  end

  it "reports a wait that ran out like a session that did not start" do
    expect(Bidi2pdf::ErrorCodes.for(Bidi2pdf::SessionStartTimeoutError.new("busy"))).to eq("BROWSER_LAUNCH_FAILED")
  end
end
