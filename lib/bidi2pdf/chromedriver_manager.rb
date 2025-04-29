# frozen_string_literal: true

require "chromedriver/binary"
require "securerandom"

module Bidi2pdf
  class ChromedriverManager
    include Chromedriver::Binary::Platform

    attr_reader :port, :pid, :started, :headless, :chrome_args, :shutdown_mutex
    attr_accessor :reader_thread

    def initialize(port: 0, headless: true, chrome_args: Bidi::Session::DEFAULT_CHROME_ARGS)
      @port = port
      @headless = headless
      @session = nil
      @started = false
      @chrome_args = chrome_args
      @shutdown_mutex ||= Mutex.new
    end

    def start
      return @pid if @pid

      @started = true

      update_chromedriver
      cmd = build_cmd
      Bidi2pdf.logger.info "Starting Chromedriver with command: #{cmd}"

      spawn_process(cmd)

      Bidi2pdf.logger.info "Started Chromedriver on port #{@port}, PID #{@pid}"
      wait_until_chromedriver_ready

      at_exit { stop }

      @pid
    end

    def session
      return unless @started

      @session ||= Bidi::Session.new(session_url: session_url, headless: @headless, chrome_args: @chrome_args)
    end

    def session_url
      return unless @started

      "http://localhost:#{@port}/session"
    end

    # rubocop: disable Metrics/AbcSize
    def stop(timeout: 5)
      shutdown_mutex.synchronize do
        return unless @pid

        if reader_thread&.alive?
          begin
            reader_thread.kill
            reader_thread.join
          rescue StandardError => e
            Bidi2pdf.logger.error "Error killing reader thread: #{e.message}"
          end
        end

        @started = false

        close_session

        debug_show_all_children

        old_childprocesses = term_chromedriver

        detect_zombie_processes old_childprocesses

        return unless process_alive?

        kill_chromedriver timeout: timeout
      ensure
        @pid = nil
        @started = false
      end
    end

    # rubocop: enable Metrics/AbcSize

    private

    def spawn_process(cmd)
      r, w = IO.pipe

      options = {
        out: w,
        err: w,
        close_others: true,
        chdir: Dir.tmpdir
      }

      if platform == "win"
        options[:new_pgroup] = true
      else
        options[:pgroup] = true
      end

      env = {}

      @pid = Process.spawn(env, cmd, **options)
      w.close # close writer in parent

      parse_port_from_output(r)
    end

    def detect_zombie_processes(old_childprocesses)
      Bidi2pdf.logger.debug "Old child processes for #{@pid}: #{old_childprocesses.map(&:pid).join(", ")}"

      zombie_processes = old_childprocesses.select { |child| process_alive? child.pid }

      return if zombie_processes.empty?

      printable_zombie_processes = zombie_processes.map { |child| "#{child.name}:#{child.pid}" }
      printable_zombie_processes_str = printable_zombie_processes.join(", ")

      Bidi2pdf.logger.error "Zombie Processes detected #{printable_zombie_processes_str}"

      term_zombie_processes zombie_processes
    end

    def term_zombie_processes(zombie_processes)
      Bidi2pdf.logger.info "Terminating zombie processes: #{zombie_processes.map(&:pid).join(", ")}"

      zombie_processes.each do |child|
        Bidi2pdf.logger.debug "Terminating PID #{child.pid} (#{child.name})"
        Process.kill("TERM", child.pid)
      end
    end

    def debug_show_all_children
      Bidi2pdf::ProcessTree.new(@pid).traverse do |process, level|
        indent = "  " * level
        prefix = level.zero? ? "" : "└─ "
        Bidi2pdf.logger.debug2 "#{indent}#{prefix}PID #{process.pid} (#{process.name})"
      end
    end

    def close_session
      Bidi2pdf.logger.info "Closing session"

      @session&.close
      @session = nil
    end

    def term_chromedriver
      Bidi2pdf::ProcessTree.new(@pid).children(@pid).tap do |_child_processes|
        Bidi2pdf.logger.info "Stopping Chromedriver (PID #{@pid})"

        Process.kill("TERM", -@pid) # - meanskill linux pgroup
      end
    rescue Errno::ESRCH
      Bidi2pdf.logger.debug "Process already gone"
      @pid = nil
    end

    def kill_chromedriver(timeout: 5)
      start_time = Time.now

      while Time.now - start_time < timeout
        return @pid = nil unless process_alive?

        sleep 0.1
      end

      Bidi2pdf.logger.warn "ChromeDriver did not terminate gracefully — force killing PID #{@pid}"

      begin
        Process.kill("KILL", @pid)
      rescue Errno::ESRCH
        Bidi2pdf.logger.debug "Process already gone"
      end
    end

    def build_cmd
      bin = Chromedriver::Binary::ChromedriverDownloader.driver_path
      user_data_dir = File.join(Dir.tmpdir, "bidi2pdf", "user_data", SecureRandom.hex(8))

      cmd = [bin]
      cmd << "--port=#{@port}" unless @port.zero?
      cmd << "--headless" if @headless
      cmd << "--user-data-dir "
      cmd << user_data_dir
      cmd.join(" ")
    end

    def update_chromedriver
      Chromedriver::Binary::ChromedriverDownloader.update
    end

    # rubocop: disable Metrics/AbcSize
    def parse_port_from_output(io, timeout: 5)
      port_event = Concurrent::Event.new

      self.reader_thread = Thread.new do
        io.each_line do |line|
          Bidi2pdf.logger.info "[chromedriver] #{line.chomp}"

          if line =~ /ChromeDriver was started successfully on port (\d+)/
            @port = ::Regexp.last_match(1).to_i if @port.nil? || @port.zero?
            port_event.set
          end
        end
      rescue IOError
        # reader closed
      ensure
        io.close unless io.closed?
      end

      return if port_event.wait(timeout)

      raise "Chromedriver did not report a usable port in #{timeout}s"
    end

    # rubocop: enable Metrics/AbcSize

    def process_alive?(pid = @pid)
      return false unless pid

      begin
        Process.waitpid(@pid, Process::WNOHANG)
        true
      rescue Errno::ESRCH, Errno::EPERM, Errno::ECHILD
        Bidi2pdf.logger.debug "Process already gone"
        false
      end
    end

    def wait_until_chromedriver_ready(timeout: 5)
      uri = URI("http://127.0.0.1:#{@port}/status")
      deadline = Time.now + timeout

      until Time.now > deadline
        begin
          response = Net::HTTP.get_response(uri)
          json = JSON.parse(response.body)
          return true if json["value"] && json["value"]["ready"]
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, JSON::ParserError
          # Just retry
        end

        sleep 0.1
      end

      raise "ChromeDriver did not become ready within #{timeout} seconds"
    end
  end
end
