# frozen_string_literal: true

require "thor"

module Bidi2pdf
  class CLI < Thor
    desc "render", "Render a URL to PDF using Chrome BiDi"
    long_desc <<~USAGE, wrap: false
      Example:

        $ bidi2pdf render \\
            --url http://localhost:3000/report \\
            --output report.pdf \\
            --cookie session=abc123 \\
            --header X-API-KEY=topsecret \\
            --auth admin:admin \\
            --headless \\
            --port 0 \\
            --wait_window_loaded \\
            --wait_network_idle \\
            --log-level debug

      This command will render the given URL to PDF using Chrome via BiDi protocol,
      optionally passing cookies, headers, and basic authentication.

      Set --port to 0 for a random ChromeDriver port.
    USAGE

    option :url, required: true, desc: "The URL to render"
    option :output, default: "output.pdf", desc: "Filename for the output PDF"
    option :cookie, type: :array, default: [], banner: "name=value", desc: "One or more cookies"
    option :header, type: :array, default: [], banner: "name=value", desc: "One or more custom headers"
    option :auth, type: :string, banner: "user:pass", desc: "Basic auth credentials"
    option :headless, type: :boolean, default: true, desc: "Run Chrome in headless mode"
    option :port, type: :numeric, default: 0, desc: "Port to run ChromeDriver on (0 = auto)"
    option :wait_window_loaded,
           type: :boolean,
           default: false,
           desc: "Wait for the window to be fully loaded (windoow.loaded set by your script)"
    option :wait_network_idle, type: :boolean, default: false, desc: "Wait for network to be idle"
    option :default_timeout, type: :numeric, default: 60, desc: "Default timeout for commands"
    option :remote_browser_url, type: :string, desc: "Remote browser URL for ChromeDriver"
    option :log_level,
           type: :string,
           default: "info", enum: %w[debug info warn error fatal unknown], desc: "Set log level"

    def render
      configure

      Bidi2pdf.logger.info "Rendering: #{options[:url]} -> #{options[:output]}"

      launcher.launch
    end

    private

    # rubocop:disable  Metrics/AbcSize
    def launcher
      # rubocop:disable Layout/BeginEndAlignment
      @launcher ||= begin
                      username, password = parse_auth(options[:auth]) if options[:auth]

                      Bidi2pdf::Launcher.new(
                        url: options[:url],
                        output: options[:output],
                        cookies: parse_key_values(options[:cookie]),
                        headers: parse_key_values(options[:header]),
                        auth: { username: username, password: password },
                        port: options[:port],
                        remote_browser_url: options[:remote_browser_url],
                        headless: options[:headless],
                        wait_window_loaded: options[:wait_window_loaded],
                        wait_network_idle: options[:wait_network_idle]
                      )
                    end
      # rubocop:enable Layout/BeginEndAlignment
    end

    # rubocop:enable Metrics/AbcSize

    def configure
      Bidi2pdf.configure do |config|
        config.logger.level = log_level
        config.default_timeout = options[:default_timeout]

        Chromedriver::Binary.configure do |c|
          c.logger.level = log_level
        end
      end
    end

    def log_level
      case options[:log_level]
      when "debug" then Logger::DEBUG
      when "warn" then Logger::WARN
      when "error" then Logger::ERROR
      when "fatal" then Logger::FATAL
      when "unknown" then Logger::UNKNOWN
      else
        Logger::INFO
      end
    end

    def parse_key_values(pairs)
      pairs.to_h do |pair|
        k, v = pair.split("=", 2)
        raise ArgumentError, "Invalid format for pair: #{pair}" unless k && v

        [k.strip, v.strip]
      end
    end

    def parse_auth(auth_string)
      user, pass = auth_string.split(":", 2)
      raise ArgumentError, "Auth must be in 'user:pass' format" unless user && pass

      [user, pass]
    end
  end
end
