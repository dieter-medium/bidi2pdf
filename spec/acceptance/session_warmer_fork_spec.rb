# frozen_string_literal: true

require "spec_helper"
require "base64"
require "json"
require "tmpdir"

# Puma's shape on a real chromedriver: the parent configures the warmer (Rails boots the app in the
# master), then forks workers that change nothing about the configuration. Each child must render on
# sessions of its own, not on the warm slot it inherited - whose WebSocket the parent still reads -
# and the parent's own warmer must go on working. Runs against its own chromedriver container, or -
# CHROME_SWEEPER_SESSION_URL set - against an existing one (a devbox sidecar), like chrome_sweeper_spec.
# Tagged :sweeper - CI runs it in that job of its own (ruby.yml, sweeper-acceptance-test).
RSpec.feature "As an operator, I want every Puma worker to render on Chrome sessions of its own", :sweeper do
  before(:all) do
    @container = start_own_chromedriver unless ENV["CHROME_SWEEPER_SESSION_URL"]
    @session_url = ENV["CHROME_SWEEPER_SESSION_URL"] || @container.session_url
    @registry_dir = Dir.mktmpdir("session-warmer-fork-spec")
    session_url = @session_url
    registry_dir = @registry_dir
    Bidi2pdf::SessionWarmer.configure do |c|
      c.size = 1
      c.chrome_args = chrome_args
      c.remote_browser_url = session_url
      c.registry_dir = registry_dir
    end
  end

  after(:all) do
    Bidi2pdf::SessionWarmer.shutdown
    FileUtils.rm_rf(@registry_dir) if @registry_dir
    @container&.stop
  end

  def start_own_chromedriver
    ChromedriverTestcontainer.new(ChromedriverTestcontainer::DEFAULT_IMAGE,
                                  build_dir: File.join(Bidi2pdf::TestHelpers.configuration.docker_dir, ".."),
                                  docker_file: "docker/Dockerfile.chromedriver").start
  end

  def chrome_args
    args = Bidi2pdf::Bidi::Session::DEFAULT_CHROME_ARGS.dup
    args << "--no-sandbox" if ENV["DISABLE_CHROME_SANDBOX"]
    args
  end

  # Seconds a forked worker gets before it is killed and the example fails - a hang must not stall CI.
  def child_timeout = 60

  def spare_session_id(warmer) = warmer.instance_variable_get(:@available).first&.dig(:session)&.session_id

  def rendered_pdf?(label)
    pdf = nil
    Bidi2pdf::SessionWarmer.with_tab do |tab|
      tab.render_html_content("<p>#{label}</p>")
      pdf = tab.print
    end
    Base64.decode64(pdf.to_s).start_with?("%PDF")
  end

  # A forked child: reports as one JSON line, exits 0 when it got that far and 1 for anything it raised.
  def fork_worker(label)
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      exit!(work_in_child(label, writer))
    end
    writer.close
    [pid, reader]
  end

  # Warms the child's own slot, renders on it, shuts the child's warmer down.
  def work_in_child(label, writer)
    Bidi2pdf::SessionWarmer.after_fork
    own = spare_session_id(Bidi2pdf::SessionWarmer.instance)
    rendered = rendered_pdf?(label)
    Bidi2pdf::SessionWarmer.shutdown
    writer.puts(JSON.generate(session: own, rendered: rendered))
    0
  rescue Exception => e # rubocop:disable Lint/RescueException -- report anything, then exit!
    warn "#{label} failed: #{e.class}: #{e.message}"
    1
  ensure
    writer.close
  end

  def collect(pid, reader)
    status = wait_or_kill(pid)
    line = reader.read.lines.last
    { exit: status&.exitstatus }.merge(line ? JSON.parse(line, symbolize_names: true) : {})
  ensure
    reader.close
  end

  # The child's exit status, or nil when it outlived child_timeout and was killed.
  def wait_or_kill(pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + child_timeout
    loop do
      status = Process.waitpid2(pid, Process::WNOHANG)&.last
      return status if status

      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        Process.kill("KILL", pid)
        Process.waitpid2(pid)
        return nil
      end
      sleep 0.1
    end
  end

  scenario "Two workers forked from a configured master" do
    before(:all) do
      @parent_session = spare_session_id(Bidi2pdf::SessionWarmer.instance)
      workers = [fork_worker("worker one"), fork_worker("worker two")]
      @results = workers.map { |pid, reader| collect(pid, reader) }
      # Read now, before any example renders: a render in the parent uses up its warm session, and
      # retiring that session rightly ends its lease - in random order that came first (CI, seed 9683).
      @leased_after_workers = Bidi2pdf::SessionRegistry.new(@session_url, dir: @registry_dir).leased
    end

    then_ "each worker rendered a real PDF" do
      expect(@results.map { |r| [r[:exit], r[:rendered]] }).to eq([[0, true], [0, true]])
    end

    then_ "each worker rendered on a session of its own, none on the parent's" do
      expect(([@parent_session] + @results.map { |r| r[:session] }).compact.uniq.size).to eq(3)
    end

    then_ "the parent's warm session outlived the workers and their shutdown" do
      expect(@leased_after_workers).to include(@parent_session)
    end

    then_ "the parent still renders" do
      expect(rendered_pdf?("parent")).to be(true)
    end
  end
end
