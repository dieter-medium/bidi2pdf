# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::SessionWarmer, :chromedriver, :nginx do
  def reporter
    RSpec.configuration.reporter
  end

  before(:all) do
    Bidi2pdf.configure { |c| c.logger.level = Logger::INFO }

    # Must be one shared mutable object, not an Integer: before(:all) ivars are handed to each example
    # by reference at example start, so `@count += 1` here (a rebind on this hook's own object) would
    # be invisible to an example that is already running.
    @slot_creations = Concurrent::AtomicFixnum.new(0)

    # Same conditional every :chromedriver-tagged spec in this repo applies against the shared
    # container's own sessions - within GitHub Actions (and this kind of nested-container setup),
    # the sandbox isn't available.
    chrome_args = Bidi2pdf::Bidi::Session::DEFAULT_CHROME_ARGS.dup
    chrome_args << "--no-sandbox" if ENV["DISABLE_CHROME_SANDBOX"]

    described_class.configure do |c|
      c.size = 2
      c.headless = true
      c.chrome_args = chrome_args
      # Remote mode: each slot/replenishment is a lightweight /session POST against the one
      # already-running shared chromedriver container, not a brand-new local chromedriver process -
      # this is what keeps the acceptance suite from spawning dozens of separate chromedriver
      # binaries and starving the container (confirmed live: that's what was happening before).
      c.remote_browser_url = session_url

      real_factory = described_class.default_slot_factory(c)
      c.slot_factory = lambda {
        @slot_creations.increment
        real_factory.call
      }
    end
  end

  after(:all) do
    described_class.shutdown
    Bidi2pdf.configure { |c| c.logger.level = Logger::FATAL }
  end

  def slot_creations
    @slot_creations.value
  end

  def with_pdf_debug(pdf_path)
    yield
  rescue RSpec::Expectations::ExpectationNotMetError => e
    reporter.message("Test failed! PDF saved to: #{pdf_path}")
    raise e
  end

  # sample.html hands its body to the (async-loaded) Paged.js polyfill, which tears it down and
  # rebuilds it as pages, then sets window.loaded. Network idle alone is not "rendered": printing
  # before window.loaded caught the page mid-rebuild and produced a blank ~1 KB PDF (confirmed in CI).
  def render_sample(tab, path)
    tab.navigate_to(nginx_url("/sample.html", use_alias: true))
    tab.wait_until_network_idle
    tab.wait_until_page_loaded
    tab.print(path)
  end

  # A blank Chrome PDF is ~1 KB and the real sample render is several hundred KB (the golden
  # sample.pdf is ~590 KB), so this sits far from both - the old 1_000 let blank pages pass.
  def min_rendered_pdf_bytes = 100_000

  # Bytes per PDF, 0 for one that was never written - so a failure shows whether a file is missing
  # or merely too small, which "all satisfy File.exist? && size > n" could not tell apart.
  def pdf_sizes(paths)
    paths.map { |path| File.exist?(path) ? File.size(path) : 0 }
  end

  # Background replenishment is async, so "a replacement was warmed" is a polled condition, not an
  # immediate one - fails loudly instead of hanging forever if it never becomes true.
  def wait_until(timeout: 15)
    deadline = Time.now + timeout
    loop do
      return true if yield
      raise "condition not met within #{timeout}s" if Time.now > deadline

      sleep 0.2
    end
  end

  describe "slot lifecycle" do
    it "pre-warms exactly config.size Chrome slots on startup" do
      # Isolated instance, not the shared singleton above: every other example in this file calls
      # the singleton's own #with_tab, which retires-and-replenishes on every single call under
      # this design - so the singleton's own creation count grows throughout the suite and an
      # absolute assertion against it would be execution-order-dependent. A fresh instance with its
      # own counter sidesteps that entirely.
      local_creations = 0
      mutex = Mutex.new
      real_factory = described_class.default_slot_factory(described_class.config)
      local_config = described_class::Configuration.new.tap do |c|
        c.size = 2
        c.chrome_args = described_class.config.chrome_args
        c.slot_factory = lambda {
          mutex.synchronize { local_creations += 1 }
          real_factory.call
        }
      end

      warmer = described_class.new(local_config, slot_factory: local_config.slot_factory)

      begin
        expect(mutex.synchronize { local_creations }).to eq(2)
      ensure
        warmer.shutdown
      end
    end

    it "consumes a warm slot without paying Chrome-startup latency, then a replacement appears asynchronously" do
      creations_before = slot_creations

      described_class.with_tab { |t| t }

      expect(wait_until(timeout: 30) { slot_creations > creations_before }).to be(true)
    end
  end

  describe "As a user rendering a single page" do
    let(:pdf_path) { tmp_file("session_warmer", "single-#{Process.pid}.pdf") }

    before { FileUtils.mkdir_p(File.dirname(pdf_path)) }
    after { FileUtils.rm_f(pdf_path) }

    it "produces a non-empty PDF file" do
      described_class.with_tab do |tab|
        render_sample(tab, pdf_path)
      end

      with_pdf_debug(pdf_path) { expect(File.size(pdf_path)).to be > min_rendered_pdf_bytes }
    end
  end

  describe "As a user rendering the same page repeatedly" do
    let(:pdf_dir) { tmp_file("session_warmer", "consecutive-#{Process.pid}") }

    before { FileUtils.mkdir_p(pdf_dir) }
    after { FileUtils.rm_rf(pdf_dir) }

    it "renders every request, warm or cold, without error" do
      paths = Array.new(3) { |i| File.join(pdf_dir, "page-#{i}.pdf") }

      paths.each do |path|
        described_class.with_tab do |tab|
          render_sample(tab, path)
        end
      end

      expect(pdf_sizes(paths)).to all(be > min_rendered_pdf_bytes)
    end
  end

  describe "As a user with concurrent rendering demand" do
    let(:pdf_dir) { tmp_file("session_warmer", "concurrent-#{Process.pid}") }

    before { FileUtils.mkdir_p(pdf_dir) }
    after { FileUtils.rm_rf(pdf_dir) }

    # Deliberately more renders than config.size: proves the never-blocks-never-raises design
    # (checkout falls back to a synchronous slot rather than queueing or failing once the warm
    # cache runs dry), which the old blocking-pool design couldn't do at all.
    #
    # Re-raises the first render failure (after every thread has finished) rather than returning
    # it - an example that only looks at the PDFs would otherwise report "file missing" instead of
    # the exception that actually caused it.
    def render_concurrently(paths)
      errors = Queue.new
      threads = paths.map do |path|
        Thread.new do
          described_class.with_tab do |tab|
            render_sample(tab, path)
          end
        rescue StandardError => e
          errors << e
        end
      end
      threads.each(&:join)
      raise errors.pop unless errors.empty?
    end

    it "serves more simultaneous renders than the warm cache holds, without error" do
      paths = Array.new(3) { |i| File.join(pdf_dir, "page-#{i}.pdf") }

      expect { render_concurrently(paths) }.not_to raise_error
    end

    it "still produces a valid, non-empty PDF for every concurrent render" do
      paths = Array.new(3) { |i| File.join(pdf_dir, "page-#{i}.pdf") }

      render_concurrently(paths)

      expect(pdf_sizes(paths)).to all(be > min_rendered_pdf_bytes)
    end
  end
end
