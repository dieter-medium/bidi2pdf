# frozen_string_literal: true

module Bidi2pdf
  # Keeps a small number of Chrome sessions pre-warmed (chromedriver started, WebSocket connected,
  # browser ready) so a render can skip that startup latency on the request path. Isolation matches
  # today's one-Chrome-per-render model exactly: every checked-out slot is used for exactly one
  # +with_tab+ block and then retired (never returned to the cache) - only a fresh replacement is
  # warmed in its place, off the request path. Checkout never waits for a warm slot: one is used if
  # it is ready, otherwise a slot is created synchronously on the spot, i.e. today's exact behavior
  # for that one render - including its failure mode: if that cold start fails, the error propagates
  # out of +with_tab+ exactly as it would without the warmer.
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
      #   A custom factory owns the cleanup of anything it half-built before raising: the warmer can
      #   only retire a slot it was actually handed.
      attr_accessor :slot_factory

      # @return [Numeric, nil] Seconds a warm slot may sit unused before it is retired and replaced.
      #   A warm slot is an open, unauthenticated automation endpoint (chromedriver's port, Chrome's
      #   debugging port) for as long as it idles, so that window is bounded by default. A slot older
      #   than this is never handed out, and a background reaper recycles idle ones within roughly
      #   1.25x this value even when no render ever comes. +nil+ disables the limit.
      attr_accessor :max_idle_age

      DEFAULT_MAX_IDLE_AGE = 300

      def initialize
        @size = 1
        @headless = true
        @chrome_args = Bidi2pdf::Bidi::Session::DEFAULT_CHROME_ARGS
        @remote_browser_url = nil
        @slot_factory = nil
        @max_idle_age = DEFAULT_MAX_IDLE_AGE
      end

      # @raise [ArgumentError] if a setting can't be honored - checked once, at construction.
      def validate!
        validate_size!
        validate_max_idle_age!
      end

      private

      def validate_size!
        return if size.is_a?(Integer) && !size.negative?

        raise ArgumentError, "size must be a non-negative Integer, got #{size.inspect}"
      end

      def validate_max_idle_age!
        return if max_idle_age.nil? || (max_idle_age.is_a?(Numeric) && max_idle_age.positive?)

        raise ArgumentError, "max_idle_age must be nil or a positive number of seconds, got #{max_idle_age.inspect}"
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
        # Cleared first: if the constructor below raises, a stale, already-shut-down instance must
        # not stay registered (it would keep serving cold slots but never warm again).
        @instance = nil
        @instance = new(@config, slot_factory: @config.slot_factory)
      end

      # Returns the warmer's configuration, initializing defaults if needed.
      def config
        @config ||= Configuration.new
      end

      # Returns a callable that creates one real, fully-warmed Chrome slot from +config+. If building
      # fails part-way (chromedriver up, but the session or its browser never came ready), whatever
      # already exists is retired before the error propagates - no caller ever gets a reference to a
      # half-built slot, so nobody else could clean it up.
      def default_slot_factory(config)
        lambda do
          parts = {}
          build_slot(config, parts)
        rescue StandardError
          retire_slot(session: parts[:session], manager: parts[:manager])
          raise
        end
      end

      # Closes a slot's session and stops its chromedriver (nil for a remote slot, or for a part that
      # was never created). Each step is independent: a failure in one is logged, never raised, and
      # never skips the other.
      def retire_slot(session:, manager:)
        safe_close("session") { session&.close }
        safe_close("manager") { manager&.stop }
      end

      def safe_close(label)
        yield
      rescue StandardError => e
        Bidi2pdf.logger.warn "session_warmer: error closing #{label}: #{e.message}"
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

      private

      # Records each part in +parts+ the moment it exists, so #default_slot_factory's rescue can
      # retire exactly what was created so far. Mirrors Launcher#session's local/remote branch.
      def build_slot(config, parts)
        config.remote_browser_url ? connect_remote(config, parts) : start_local(config, parts)

        { session: parts[:session], browser: parts[:session].browser, manager: parts[:manager] }
      end

      def connect_remote(config, parts)
        parts[:session] = Bidi2pdf::Bidi::Session.new(
          session_url: config.remote_browser_url,
          headless: config.headless,
          chrome_args: config.chrome_args
        )
      end

      def start_local(config, parts)
        parts[:manager] = Bidi2pdf::ChromedriverManager.new(port: 0, headless: config.headless, chrome_args: config.chrome_args)
        parts[:manager].start
        parts[:session] = parts[:manager].session
      end
    end

    def initialize(config, slot_factory: nil)
      config.validate!
      @config = config
      @slot_factory = slot_factory || self.class.default_slot_factory(config)
      @mutex = Mutex.new
      @available = []
      @replenish_threads = []
      @warming = 0
      @shutdown = false
      @reaper_wakeup = Thread::Queue.new
      prewarm
      @reaper = Thread.new { reap_loop } if @config.max_idle_age
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
    # #stash_or_retire). A subsequent #with_tab still works - it just falls back to a synchronous
    # slot, since checkout never depends on a warm one being there.
    def shutdown
      spares, threads = @mutex.synchronize do
        @shutdown = true
        [@available.dup.tap { @available.clear }, @replenish_threads.dup.tap { @replenish_threads.clear }]
      end

      @reaper_wakeup << :stop
      @reaper&.join
      threads.each(&:join)
      spares.each { |slot| retire(slot) }
    end

    private

    # Fail-fast on purpose (a Chrome that can't start at boot should be loud), but not leaky: if slot
    # N fails, no instance is returned to own slots 1..N-1, so they are retired here first.
    def prewarm
      @config.size.times { @available << stamp(create_slot) }
    rescue StandardError
      @available.each { |slot| retire(slot) }
      @available.clear
      raise
    end

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

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # Marks the moment a slot entered the cache - idle age counts from here, not from when its
    # Chrome started, since it is the unattended waiting that max_idle_age bounds.
    def stamp(slot)
      slot.merge(warmed_at: now)
    end

    def expired?(slot)
      !@config.max_idle_age.nil? && now - slot[:warmed_at] > @config.max_idle_age
    end

    # Checkout alone can't bound idle time: with no traffic nothing would ever look at a spare. This
    # thread does, four times per max_idle_age, so an unused slot is recycled within ~1.25x of it.
    # Thread::Queue#pop(timeout:) doubles as an interruptible sleep - #shutdown pushes :stop.
    def reap_loop
      interval = [@config.max_idle_age / 4.0, 0.05].max
      recycle_expired until @reaper_wakeup.pop(timeout: interval) == :stop
    end

    def recycle_expired
      expired = @mutex.synchronize do
        next [] if @shutdown

        old, fresh = @available.partition { |slot| expired?(slot) }
        @available.replace(fresh)
        old
      end
      return if expired.empty?

      Bidi2pdf.notification_service.instrument("session_warmer.expired.bidi2pdf", { count: expired.size })
      replenish_async
      expired.each { |slot| retire(slot) }
    rescue StandardError => e
      Bidi2pdf.logger.warn "session_warmer: recycling idle slots failed: #{e.message}"
    end

    # A warm hit takes the spare and triggers a background replacement; a miss (empty cache, or a
    # spare that died while idle) falls straight through to a synchronous slot - it never waits, so
    # an under-provisioned warmer is never worse than not having one. A cold start that fails raises,
    # as it would without the warmer.
    #
    # Oldest spare first (shift, not pop), so no slot lingers at the bottom of the cache while newer
    # ones are used; and one past max_idle_age is never handed out, even if the reaper hasn't got to
    # it yet - it is retired like a dead spare and this render cold-starts instead.
    def checkout
      slot = @mutex.synchronize { @available.shift }
      had_spare = !slot.nil?
      hit = had_spare && !expired?(slot) && healthy?(slot)
      taken = nil

      Bidi2pdf.notification_service.instrument("session_warmer.checkout.bidi2pdf", { hit: hit }) do
        taken = hit ? slot : cold_checkout(slot)
      end

      # Every checkout tops the cache back up, hit or miss - #replenish_async itself bounds the work
      # to the current deficit, so a miss on an already-full-or-filling cache starts nothing.
      replenish_async
      taken
    end

    def cold_checkout(dead_slot)
      retire(dead_slot) if dead_slot
      create_slot
    end

    # Tops the cache up towards config.size, counting warmers already in flight. Deficit-based on
    # purpose, not "replace what this checkout popped": that rule could never recover from a single
    # failed warm (nothing stashed -> every later checkout a miss -> never replenished again), while
    # replenishing unconditionally let @available grow without bound under a burst of misses.
    # available + warming never exceeds config.size, and a failed warm frees its reservation, so the
    # next checkout simply tries again.
    #
    # Threads are created and registered inside the same critical section, so #shutdown's snapshot
    # can't miss one that has started but isn't listed yet (#warm_one needs this mutex to finish,
    # so it just waits for it).
    def replenish_async
      @mutex.synchronize do
        next if @shutdown

        @replenish_threads.select!(&:alive?)
        deficit = @config.size - (@available.size + @warming)
        deficit.times do
          @warming += 1
          @replenish_threads << Thread.new { warm_one }
        end
      end
    end

    def warm_one
      slot = create_slot
    rescue StandardError => e
      @mutex.synchronize { @warming -= 1 }
      Bidi2pdf.logger.warn "session_warmer: failed to warm a replacement slot: #{e.message}"
      Bidi2pdf.notification_service.instrument("session_warmer.warm_failed.bidi2pdf", { error: e.class.name })
    else
      stash_or_retire(slot)
    end

    # A replacement warmed after #shutdown has nothing to stash into - retire it immediately rather
    # than leaking a live Chrome process that nothing will ever check out. Either way this warmer's
    # reservation is released here, in the same critical section as the stash.
    def stash_or_retire(slot)
      discard = @mutex.synchronize do
        @warming -= 1

        if @shutdown
          true
        else
          @available << stamp(slot)
          false
        end
      end

      retire(slot) if discard
    end

    def retire(slot)
      self.class.retire_slot(session: slot[:session], manager: slot[:manager])
    end

    def safe_close(label, &)
      self.class.safe_close(label, &)
    end
  end
end
