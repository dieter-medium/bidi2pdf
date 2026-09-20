# frozen_string_literal: true

module Bidi2pdf
  # Keeps a small number of Chrome sessions pre-warmed (chromedriver started, WebSocket connected,
  # browser ready) so a render can skip that startup latency on the request path. Isolation matches
  # today's one-Chrome-per-render model exactly: every checked-out slot is used for exactly one
  # +with_tab+ block and then retired (never returned to the cache) - only a fresh replacement is
  # warmed in its place, off the request path. Checkout never blocks or raises: a warm slot is used
  # if one is ready, otherwise a slot is created synchronously on the spot, i.e. today's exact
  # behavior for that one render.
  #
  # @example Rails initializer
  #   Bidi2pdf::SessionWarmer.configure do |c|
  #     c.size = 2
  #     c.headless = true
  #   end
  #
  # @example Per-request usage
  #   Bidi2pdf::SessionWarmer.with_tab do |tab|
  #     tab.navigate_to(url)
  #     tab.print("invoice.pdf")
  #   end
  class SessionWarmer
    # Configuration for the session warmer.
    class Configuration
      # @return [Integer] Number of Chrome slots to keep pre-warmed.
      attr_accessor :size

      # @return [Boolean] Whether to run Chrome in headless mode.
      attr_accessor :headless

      # @return [Array<String>] Chrome launch arguments.
      attr_accessor :chrome_args

      # @return [String, nil] A remote chromedriver session URL (e.g. a `remote-chrome` sidecar). When
      #   set, a slot connects directly to it instead of spawning a local ChromedriverManager -
      #   mirrors Launcher#session's own local/remote branch.
      attr_accessor :remote_browser_url

      # @return [#call, nil] Optional factory callable that returns a slot hash - injectable for tests.
      attr_accessor :slot_factory

      def initialize
        @size = 1
        @headless = true
        @chrome_args = Bidi2pdf::Bidi::Session::DEFAULT_CHROME_ARGS
        @remote_browser_url = nil
        @slot_factory = nil
      end
    end

    class << self
      # Configures the warmer and eagerly (re)creates the singleton, warming config.size slots right
      # here - at boot/configuration time, off the request path - instead of lazily on whichever
      # request happens to trigger the first #with_tab (which would otherwise pay for every
      # configured slot, serially, on that one unlucky request).
      def configure
        @config = Configuration.new
        yield @config if block_given?
        @instance&.shutdown
        @instance = new(@config, slot_factory: @config.slot_factory)
      end

      # Returns the warmer's configuration, initializing defaults if needed.
      def config
        @config ||= Configuration.new
      end

      # Returns a callable that creates one real, fully-warmed Chrome slot from +config+.
      def default_slot_factory(config)
        lambda do
          if config.remote_browser_url
            session = Bidi2pdf::Bidi::Session.new(
              session_url: config.remote_browser_url,
              headless: config.headless,
              chrome_args: config.chrome_args
            )
            { session: session, browser: session.browser, manager: nil }
          else
            manager = Bidi2pdf::ChromedriverManager.new(port: 0, headless: config.headless, chrome_args: config.chrome_args)
            manager.start
            session = manager.session
            { session: session, browser: session.browser, manager: manager }
          end
        end
      end

      # Returns the shared singleton warmer instance, creating it (and pre-warming it) on first call.
      def instance
        @instance ||= new(config, slot_factory: config.slot_factory)
      end

      # Checks out a slot, yields a fresh tab for one render, then retires the slot.
      def with_tab(&)
        instance.with_tab(&)
      end

      # Retires every currently-warm spare and resets the singleton.
      def shutdown
        @instance&.shutdown
        @instance = nil
      end
    end

    def initialize(config, slot_factory: nil)
      @config = config
      @slot_factory = slot_factory || self.class.default_slot_factory(config)
      @mutex = Mutex.new
      @available = []
      @replenish_threads = []
      @shutdown = false
      @config.size.times { @available << create_slot }
    end

    # Checks out a slot, creates an isolated UserContext/Window/Tab for one render, yields the tab,
    # then unconditionally closes those resources and retires the underlying slot.
    def with_tab
      slot = checkout
      user_context = nil
      window = nil
      tab = nil

      begin
        user_context = slot[:browser].create_user_context
        window = user_context.create_browser_window
        tab = window.create_browser_tab
        yield tab
      ensure
        safe_close("tab") { tab&.close }
        safe_close("window") { window&.close }
        safe_close("user context") { user_context&.close }
        retire(slot)
      end
    end

    # Retires every currently-warm spare and waits for any in-flight background replenishment to
    # finish (each of those, seeing @shutdown, retires its own result instead of stashing it - see
    # #stash_or_retire). A subsequent #with_tab still works (falls back to a synchronous slot),
    # matching checkout's own never-blocks-never-raises design.
    def shutdown
      spares, threads = @mutex.synchronize do
        @shutdown = true
        [@available.dup.tap { @available.clear }, @replenish_threads.dup.tap { @replenish_threads.clear }]
      end

      threads.each(&:join)
      spares.each { |slot| retire(slot) }
    end

    private

    def create_slot
      @slot_factory.call
    end

    # Session#started? is just an internal flag set once at startup - it never flips back if Chrome,
    # ChromeDriver, or the WebSocket dies externally while a slot sits idle in the cache. The
    # client's own #open? is kept live by the reader thread noticing a real socket error, so
    # checking it too catches that case - cheap (no network round trip), though still a heuristic,
    # not a full liveness guarantee (a stuck-but-not-yet-disconnected socket still reads healthy).
    def healthy?(slot)
      slot[:session].started? && slot[:session].client&.open? == true
    end

    # A warm hit takes the spare and triggers a background replacement; a miss (empty cache, or a
    # spare that died while idle) falls straight through to a synchronous slot - never blocks or
    # raises, so an under-provisioned warmer is never worse than not having one.
    def checkout
      slot = @mutex.synchronize { @available.pop }
      had_spare = !slot.nil?
      hit = had_spare && healthy?(slot)
      taken = nil

      Bidi2pdf.notification_service.instrument("session_warmer.checkout.bidi2pdf", { hit: hit }) do
        taken = hit ? slot : cold_checkout(slot)
      end

      # Replenish exactly what was actually removed from @available (a healthy hit, or a dead spare
      # discarded below) - never on an empty-cache miss, which took nothing from it. Firing
      # unconditionally here let @available grow past config.size without bound under concurrent
      # misses: each one created a synchronous cold slot *and* a background spare, forever.
      replenish_async if had_spare
      taken
    end

    def cold_checkout(dead_slot)
      retire(dead_slot) if dead_slot
      create_slot
    end

    def replenish_async
      thread = Thread.new { warm_one }

      @mutex.synchronize do
        @replenish_threads.reject!(&:alive?)
        @replenish_threads << thread
      end

      thread
    end

    def warm_one
      slot = create_slot
    rescue StandardError => e
      Bidi2pdf.logger.warn "session_warmer: failed to warm a replacement slot: #{e.message}"
      Bidi2pdf.notification_service.instrument("session_warmer.warm_failed.bidi2pdf", { error: e.class.name })
    else
      stash_or_retire(slot)
    end

    # A replacement warmed after #shutdown has nothing to stash into - retire it immediately rather
    # than leaking a live Chrome process that nothing will ever check out.
    def stash_or_retire(slot)
      discard = @mutex.synchronize do
        if @shutdown
          true
        else
          @available << slot
          false
        end
      end

      retire(slot) if discard
    end

    def retire(slot)
      safe_close("session") { slot[:session].close }
      safe_close("manager") { slot[:manager]&.stop }
    end

    def safe_close(label)
      yield
    rescue StandardError => e
      Bidi2pdf.logger.warn "session_warmer: error closing #{label}: #{e.message}"
    end
  end
end
