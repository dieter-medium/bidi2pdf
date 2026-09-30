# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tmpdir"

# Real leaked sessions on a real chromedriver: a child process opens a session and dies with exit!,
# exactly what a killed Puma worker or a crashed job leaves behind. The spec runs against its own
# chromedriver container, or - CHROME_SWEEPER_SESSION_URL set - against an existing one (a devbox
# sidecar). On a shared chromedriver every session this spec did not open counts as "own" for every
# sweeper here, so nothing but the spec's own sessions can ever be closed.
# Tagged :sweeper - CI runs it in a job of its own (ruby.yml, sweeper-acceptance-test).
RSpec.feature "As an operator, I want leaked Chrome sessions closed before they exhaust the chromedriver", :sweeper do
  def orphan_script = <<~RUBY
    require "bidi2pdf"
    Bidi2pdf.logger.level = Logger::FATAL
    url, registry_dir, mode = ARGV
    Bidi2pdf::SessionRegistry::Heartbeat.interval = 0.5
    args = Bidi2pdf::Bidi::Session::DEFAULT_CHROME_ARGS.dup
    args << "--no-sandbox" if ENV["DISABLE_CHROME_SANDBOX"]
    registry = registry_dir.empty? ? nil : Bidi2pdf::SessionRegistry.new(url, dir: registry_dir)
    session = Bidi2pdf::Bidi::Session.new(session_url: url, chrome_args: args, registry: registry)
    session.start
    started_at = Time.now.to_f
    session.browser
    if mode == "hang"
      tree = session.client.send_cmd_and_wait(Bidi2pdf::Bidi::Commands::BrowsingContextGetTree.new)
      context = tree.dig("result", "contexts", 0, "context")
      session.client.send_cmd(Bidi2pdf::Bidi::Commands::ScriptEvaluate.new(expression: "while (true) {}", context: context))
      sleep 0.5
    end
    puts "\#{session.session_id} \#{started_at}"
    $stdout.flush
    sleep if mode == "live"
    exit!(0)
  RUBY

  # A child renews every 0.5 s, so its lease entries carry a TTL of 1.5 s (three heartbeats) - a
  # dead child's lease runs out after that, plus the second the registry rounds to.
  def child_lease_ttl = 1.5

  before(:all) do
    @container = start_own_chromedriver unless ENV["CHROME_SWEEPER_SESSION_URL"]
    @session_url = ENV["CHROME_SWEEPER_SESSION_URL"] || @container.session_url
    @registry_dir = Dir.mktmpdir("chrome-sweeper-spec")
    @created = []
    @started_at = {}
    @workers = []
    @live = open_session
  end

  after(:all) do
    @live&.close
    @workers&.each do |io|
      Process.kill("KILL", io.pid)
    rescue Errno::ESRCH
      nil
    end
    @created&.each { |id| api.delete_session(id) }
    FileUtils.rm_rf(@registry_dir) if @registry_dir
    stop_container(@container) if @container
  end

  def start_own_chromedriver
    ChromedriverTestcontainer.new(ChromedriverTestcontainer::DEFAULT_IMAGE,
                                  build_dir: File.join(Bidi2pdf::TestHelpers.configuration.docker_dir, ".."),
                                  docker_file: "docker/Dockerfile.chromedriver").start
  end

  def api = Bidi2pdf::ChromedriverApi.new(@session_url)

  def registry = Bidi2pdf::SessionRegistry.new(@session_url, dir: @registry_dir)

  def chrome_args
    args = Bidi2pdf::Bidi::Session::DEFAULT_CHROME_ARGS.dup
    args << "--no-sandbox" if ENV["DISABLE_CHROME_SANDBOX"]
    args
  end

  def open_session
    session = Bidi2pdf::Bidi::Session.new(session_url: @session_url, chrome_args: chrome_args, registry: registry)
    session.start
    session.browser
    @created << session.session_id
    session
  end

  # A session opened by a process that then died without closing it.
  def orphan(recorded: true, hang: false)
    out, err, status = Open3.capture3("ruby", "-Ilib", "-e", orphan_script, @session_url, recorded ? @registry_dir : "", hang ? "hang" : "",
                                      chdir: File.expand_path("../..", __dir__))
    id, started_at = out.lines.last.to_s.split
    raise "orphan process failed (#{status.inspect}): #{err}" if id.nil?

    note_start(id, started_at.to_f)
  end

  def note_start(id, started_at)
    @created << id
    @started_at[id] = started_at
    @leases_expire_at = started_at.ceil + child_lease_ttl + 1
    id
  end

  # A process that keeps rendering: holds its session, keeps renewing the lease, never exits.
  # Returns [session id, pid].
  def live_worker
    io = IO.popen(["ruby", "-Ilib", "-e", orphan_script, @session_url, @registry_dir, "live"],
                  chdir: File.expand_path("../..", __dir__))
    id = io.gets.to_s.split.first
    raise "worker process failed" if id.nil?

    @created << id
    @workers << io
    [id, io.pid]
  end

  # A crashed process looks alive until its lease ran out - sweeps here wait for that.
  def wait_for_dead_leases
    wait = @leases_expire_at.to_f - Time.now.to_f
    sleep wait if wait.positive?
  end

  # Seconds since the orphan's process saw its session start.
  def real_age(id) = Time.now.to_f - @started_at[id]

  # Everything on the chromedriver the spec did not open, plus the spec's own live session, looked
  # up at sweep time - so a session another client opens meanwhile is protected too.
  def protected_sessions
    -> { (api.sessions.map(&:id) - @created) << @live.session_id }
  end

  def sweeper(**)
    wait_for_dead_leases
    Bidi2pdf::ChromeSweeper.new(@session_url, registry: registry, own_sessions: protected_sessions,
                                              orphan_age: nil, unresponsive_checks: nil, min_age: 0,
                                              inspector: Bidi2pdf::ChromeSweeper::Inspector.new(timeout: 2), **)
  end

  def open_ids = api.sessions.map(&:id)

  # Leftovers of one example must not become the oldest sessions of the next.
  def drop(*ids) = ids.flatten.compact.each { |id| api.delete_session(id) }

  def info_for(id) = sweeper(scope: :all).sessions.find { |info| info.id == id }

  scenario "Looking at what a chromedriver holds" do
    before(:all) do
      @recorded = orphan(recorded: true)
      @unrecorded = orphan(recorded: false)
      sleep 2
    end

    after(:all) { [@recorded, @unrecorded].each { |id| api.delete_session(id) } }

    then_ "a session bidi2pdf recorded is aged from the record" do
      expect(info_for(@recorded).age).to be_within(2).of(real_age(@recorded))
    end

    then_ "a session nobody recorded is aged from its first tab" do
      expect(info_for(@unrecorded).age).to be_within(2).of(real_age(@unrecorded))
    end

    then_ "the age of a session nobody recorded comes from its tab" do
      expect(info_for(@unrecorded).source).to eq(:tab)
    end
  end

  scenario "Sweeping every session on a chromedriver the application owns" do
    before do
      @orphans = [orphan(recorded: true), orphan(recorded: false)]
      sleep 1.5
    end

    after { drop(@orphans) }

    then_ "both leftovers are closed, recorded or not" do
      sweeper(scope: :all, orphan_age: 1).sweep!

      expect(open_ids & @orphans).to be_empty
    end

    then_ "the application's own live session is kept" do
      sweeper(scope: :all, orphan_age: 1).sweep!

      expect(open_ids).to include(@live.session_id)
    end

    then_ "a dry run closes nothing" do
      sweeper(scope: :all, orphan_age: 1, dry_run: true).sweep!

      expect(open_ids).to include(*@orphans)
    end

    then_ "a dry run reports what it would close" do
      result = sweeper(scope: :all, orphan_age: 1, dry_run: true).sweep!

      expect(result.closed.map(&:id)).to include(*@orphans)
    end
  end

  scenario "Sweeping only the sessions bidi2pdf recorded" do
    before do
      @recorded = orphan(recorded: true)
      @unrecorded = orphan(recorded: false)
      sleep 1.5
    end

    after { drop(@recorded, @unrecorded) }

    then_ "the recorded leftover is closed" do
      sweeper(scope: :recorded, orphan_age: 1).sweep!

      expect(open_ids).not_to include(@recorded)
    end

    then_ "a session another tool opened is left alone" do
      sweeper(scope: :recorded, orphan_age: 1).sweep!

      expect(open_ids).to include(@unrecorded)
    end
  end

  scenario "Keeping the number of sessions under a limit" do
    before do
      @older = orphan(recorded: true)
      sleep 3
      @younger = orphan(recorded: true)
      wait_for_dead_leases
    end

    after { drop(@older, @younger) }

    def limit_room(extra) = (api.sessions.map(&:id) - [@older, @younger]).size + extra

    # Halfway between the two sessions' real ages - whatever a slow process start added to both.
    def min_age_between = (real_age(@older) + real_age(@younger)) / 2

    then_ "the oldest session goes first" do
      sweeper(scope: :all, max_sessions: limit_room(1)).sweep!

      expect([open_ids.include?(@older), open_ids.include?(@younger)]).to eq([false, true])
    end

    then_ "a session younger than min_age is kept even over the limit" do
      sweeper(scope: :all, max_sessions: limit_room(0), min_age: min_age_between).sweep!

      expect(open_ids).to include(@younger)
    end

    then_ "a limit that cannot be reached is reported" do
      result = sweeper(scope: :all, max_sessions: limit_room(0), min_age: min_age_between).sweep!

      expect(result.limit_exceeded).to be(true)
    end
  end

  scenario "A tab stuck in an endless loop" do
    then_ "closing its session still gets rid of it" do
      session = open_session
      context = session.client.send_cmd_and_wait(Bidi2pdf::Bidi::Commands::BrowsingContextGetTree.new).dig("result", "contexts", 0, "context")
      session.client.send_cmd(Bidi2pdf::Bidi::Commands::ScriptEvaluate.new(expression: "while (true) {}", context: context))
      sleep 1

      session.close

      expect(open_ids).not_to include(session.session_id)
    ensure
      drop(session&.session_id)
    end

    then_ "a leftover session stuck in a loop is closed once it failed the configured number of checks" do
      hung = orphan(recorded: false, hang: true)
      watcher = sweeper(scope: :all, unresponsive_checks: 2)

      2.times { watcher.sweep! }

      expect(open_ids).not_to include(hung)
    ensure
      drop(hung)
    end

    then_ "a single failed check is not enough" do
      hung = orphan(recorded: false, hang: true)

      sweeper(scope: :all, unresponsive_checks: 2).sweep!

      expect(open_ids).to include(hung)
    ensure
      drop(hung)
    end
  end

  scenario "Another worker is still rendering" do
    then_ "even a last-resort sweep leaves its session alone" do
      id, = live_worker

      sweeper(scope: :all).sweep!(pressure: true)

      expect(open_ids).to include(id)
    ensure
      drop(id)
    end

    then_ "once that worker is killed, its session goes when the lease ran out" do
      id, pid = live_worker
      Process.kill("KILL", pid)
      sleep child_lease_ttl + 2

      sweeper(scope: :all).sweep!(pressure: true)

      expect(open_ids).not_to include(id)
    ensure
      drop(id)
    end
  end
end
