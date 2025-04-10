# frozen_string_literal: true

require "chromedriver/binary"
require "securerandom"

module Bidi2pdf
  class ChromedriverManager
    attr_reader :port, :pid, :started

    def initialize(port: 0, headless: true)
      @port = port
      @headless = headless
      @session = nil
      @started = false
    end

    def start
      return @pid if @pid

      @started = true

      update_chromedriver
      cmd = build_cmd
      Bidi2pdf.logger.info "Starting Chromedriver with command: #{cmd}"

      r, w = IO.pipe
      @pid = Process.spawn(cmd, out: w, err: w)
      w.close # close writer in parent

      parse_port_from_output(r)

      Bidi2pdf.logger.info "Started Chromedriver on port #{@port}, PID #{@pid}"
      wait_until_chromedriver_ready

      at_exit { stop }

      @pid
    end

    def session
      return unless @started

      @session ||= Bidi::Session.new(session_url: session_url, headless: @headless)
    end

    def session_url
      return unless @started

      "http://localhost:#{@port}/session"
    end

    def stop(timeout: 5)
      return unless @pid

      @started = false

      close_session

      debug_show_all_children

      old_childprocesses = term_chromedriver

      detect_zombie_processes old_childprocesses

      return unless process_alive?

      kill_chromedriver timeout: timeout
    ensure
      @pid = nil
    end

    private

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
        Bidi2pdf.logger.debug "#{indent}#{prefix}PID #{process.pid} (#{process.name})"
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

        Process.kill("TERM", @pid)
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
      Thread.new do
        io.each_line do |line|
          Bidi2pdf.logger.debug line.chomp

          next unless line =~ /ChromeDriver was started successfully on port (\d+)/

          Bidi2pdf.logger.debug "Found port: #{::Regexp.last_match(1).to_i} setup port: #{@port}"

          @port = ::Regexp.last_match(1).to_i if @port.nil? || @port.zero?

          break
        end
      rescue IOError
        # reader closed
      ensure
        io.close unless io.closed?
      end.join(timeout)

      raise "Chromedriver did not report a usable port in #{timeout}s" if @port.nil?
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
