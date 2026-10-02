# frozen_string_literal: true

require "spec_helper"
require "open3"
require "socket"
require "tmpdir"

# docker/chromedriver-watchdog.sh, run for real against a stand-in chromedriver: a sleeping process
# for the pid, a tiny HTTP server for /status, a file for the cgroup's memory pressure.
# rubocop:disable-next RSpec/DescribeClass -- a shell script in the image, not a Ruby class.
RSpec.describe "docker/chromedriver-watchdog.sh" do
  let(:script) { File.expand_path("../../../docker/chromedriver-watchdog.sh", __dir__) }
  let(:dir) { Dir.mktmpdir }
  let(:pressure_file) { File.join(dir, "memory.pressure") }
  let(:chromedriver) { Process.spawn("sleep", "60") }
  let(:reaper) { Process.detach(chromedriver) }

  before { reaper }

  after do
    Process.kill("KILL", chromedriver) if reaper.alive?
    @status_server&.close
    FileUtils.rm_rf(dir)
  end

  # Answers every request with 200 until the spec ends.
  def status_port
    @status_server = TCPServer.new("127.0.0.1", 0)
    Thread.new do
      loop do
        client = @status_server.accept
        client.readpartial(4096)
        client.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}")
        client.close
      rescue IOError, SystemCallError
        break
      end
    end
    @status_server.addr[1]
  end

  # A port nothing listens on.
  def closed_port
    server = TCPServer.new("127.0.0.1", 0)
    server.addr[1].tap { server.close }
  end

  def pressure(full_avg10)
    File.write(pressure_file, "some avg10=0.00 avg60=0.00 avg300=0.00 total=0\n" \
                              "full avg10=#{full_avg10} avg60=0.00 avg300=0.00 total=0\n")
  end

  def marker = File.join(dir, "restarted")

  def watch(port:, **env)
    settings = { "CHROMEDRIVER_PORT" => port.to_s, "WATCHDOG_INTERVAL" => "1", "WATCHDOG_FAILURES" => "2",
                 "WATCHDOG_STATUS_TIMEOUT" => "1", "WATCHDOG_PRESSURE_FILE" => pressure_file }
    Open3.popen3(settings.merge(env), "bash", script, chromedriver.to_s, marker)
  end

  def chromedriver_stopped_within?(seconds)
    !reaper.join(seconds).nil?
  end

  def stop(watcher)
    Process.kill("TERM", watcher.last.pid)
  rescue Errno::ESRCH
    nil
  ensure
    watcher.last.join
  end

  it "leaves a chromedriver that answers and has memory to spare alone" do
    pressure("3.10")
    watcher = watch(port: status_port)

    expect(chromedriver_stopped_within?(4)).to be(false)
  ensure
    stop(watcher)
  end

  it "stops a chromedriver that no longer answers /status" do
    watcher = watch(port: closed_port)

    expect(chromedriver_stopped_within?(6)).to be(true)
  ensure
    stop(watcher)
  end

  it "stops chromedriver while memory thrashes" do
    pressure("72.40")
    watcher = watch(port: status_port)

    expect(chromedriver_stopped_within?(6)).to be(true)
  ensure
    stop(watcher)
  end

  it "ignores memory pressure when its limit is 0" do
    pressure("99.00")
    watcher = watch(port: status_port, "WATCHDOG_MEMORY_PRESSURE" => "0")

    expect(chromedriver_stopped_within?(4)).to be(false)
  ensure
    stop(watcher)
  end

  it "leaves the marker that makes the container exit non-zero" do
    watcher = watch(port: closed_port)
    chromedriver_stopped_within?(6)

    expect(File).to exist(marker)
  ensure
    stop(watcher)
  end

  it "leaves no marker while chromedriver is fine" do
    watcher = watch(port: status_port)
    chromedriver_stopped_within?(3)

    expect(File).not_to exist(marker)
  ensure
    stop(watcher)
  end

  it "reads a zero-padded limit as decimal, not octal" do
    pressure("45.00")
    watcher = watch(port: status_port, "WATCHDOG_MEMORY_PRESSURE" => "050")

    expect(chromedriver_stopped_within?(4)).to be(false)
  ensure
    stop(watcher)
  end

  it "accepts a zero-padded number that is no valid octal number" do
    pressure("9.00")
    watcher = watch(port: status_port, "WATCHDOG_MEMORY_PRESSURE" => "08", "WATCHDOG_STOP_GRACE" => "09")

    expect(chromedriver_stopped_within?(6)).to be(true)
  ensure
    stop(watcher)
  end

  it "says why it restarts" do
    _, _, stderr, thread = watch(port: closed_port)
    thread.join(8)

    expect(stderr.read).to include("did not answer /status", "restarting")
  end

  it "refuses a malformed setting instead of watching" do
    _, _, stderr, thread = watch(port: status_port, "WATCHDOG_INTERVAL" => "1; rm -rf /")

    expect([thread.value.exitstatus, stderr.read]).to match([1, /WATCHDOG_INTERVAL must be an integer/])
  end

  it "leaves chromedriver running when it refuses a setting" do
    _, _, _, thread = watch(port: status_port, "WATCHDOG_FAILURES" => "0")
    thread.join

    expect(reaper.alive?).to be(true)
  end
end
