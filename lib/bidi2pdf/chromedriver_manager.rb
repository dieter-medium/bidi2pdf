# frozen_string_literal: true

require "chromedriver/binary"

module Bidi2pdf
  class ChromedriverManager
    attr_reader :port, :pid, :session

    def initialize(port: 0, headless: true)
      @port = port
      @headless = headless
      @session = nil
    end

    def start
      return @pid if @pid

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

      @session = Bidi::Session.new(@port, headless: @headless)

      @pid
    end

    def stop(timeout: 5)
      return unless @pid

      close_session

      term_chromedriver

      return unless process_alive?

      kill_chromedriver timeout: timeout
    ensure
      @pid = nil
    end

    private

    def close_session
      Bidi2pdf.logger.info "Closing session"

      @session.close
      @session = nil
    end

    def term_chromedriver
      Bidi2pdf.logger.info "Stopping Chromedriver (PID #{@pid})"

      Process.kill("TERM", @pid)
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
      user_data_dir = File.join(Dir.tmpdir, "bidi2pdf", "user_data")

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

    def process_alive?
      return false unless @pid

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
