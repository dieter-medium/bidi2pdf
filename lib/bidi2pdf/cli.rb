# frozen_string_literal: true

require "thor"
require "yaml"

module Bidi2pdf
  # rubocop:disable Metrics/AbcSize
  class CLI < Thor
    class_option :config, type: :string, desc: "Load configuration from YAML file"

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

    option :url, desc: "The URL to render"
    option :output, default: "output.pdf", desc: "Filename for the output PDF", aliases: "-o"
    option :cookie, type: :array, default: [], banner: "name=value", desc: "One or more cookies", aliases: "-C"
    option :header, type: :array, default: [], banner: "name=value", desc: "One or more custom headers", aliases: "-H"
    option :auth, type: :string, banner: "user:pass", desc: "Basic auth credentials", aliases: "-a"
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

    option :background, type: :boolean, default: true, desc: "Print background graphics"
    option :margin_top, type: :numeric, default: 1.0, desc: "Top margin in inches"
    option :margin_bottom, type: :numeric, default: 1.0, desc: "Bottom margin in inches"
    option :margin_left, type: :numeric, default: 1.0, desc: "Left margin in inches"
    option :margin_right, type: :numeric, default: 1.0, desc: "Right margin in inches"
    option :orientation, type: :string, default: "portrait", enum: %w[portrait landscape], desc: "Page orientation"
    option :page_width, type: :numeric, default: 21.59, desc: "Page width in cm (min 0.0352)"
    option :page_height, type: :numeric, default: 27.94, desc: "Page height in cm (min 0.0352)"
    option :page_ranges, type: :array, desc: "Page ranges to print (e.g., 1-2 4 6)"
    option :scale, type: :numeric, default: 1.0, desc: "Scale between 0.1 and 2.0"
    option :shrink_to_fit, type: :boolean, default: true, desc: "Shrink content to fit page"

    def render
      load_config

      validate_required_options! :url

      configure

      Bidi2pdf.logger.info "Rendering: #{merged_options[:url]} -> #{merged_options[:output]}"
      Bidi2pdf.logger.info "Print options: #{print_options.inspect}" if print_options

      validate_print_options(print_options) if print_options

      launcher.launch
    rescue StandardError => e
      Bidi2pdf.logger.error "Error: #{e.message}"
      exit 1
    ensure
      launcher.stop if defined?(@launcher) && @launcher
    end

    desc "version", "Show bidi2pdf version"

    def version
      puts "bidi2pdf #{Bidi2pdf::VERSION}"
    end

    desc "template", "Generate a config file template"
    option :output, default: "bidi2pdf.yml", desc: "Output configuration filename"

    def template
      config = {
        "url" => "https://example.com",
        "output" => "output.pdf",
        "headless" => true,
        "print_options" => {
          "background" => true,
          "orientation" => "portrait",
          "margin" => {
            "top" => 1.0,
            "bottom" => 1.0,
            "left" => 1.0,
            "right" => 1.0
          }
        }
      }

      File.write(merged_options[:output], config.to_yaml)
      puts "Config template written to #{merged_options[:output]}"
    end

    private

    def load_config
      return unless options[:config] && File.exist?(options[:config])

      YAML.load_file(options[:config]).transform_keys(&:to_sym)
    end

    def validate_required_options!(*keys)
      keys.each do |key|
        raise Thor::Error, "Missing required option: --#{key.to_s.tr("_", "-")}" unless merged_options[key]
      end
    end

    def validate_print_options(opts)
      Bidi2pdf::Bidi::PrintParametersValidator.validate!(opts)
    rescue ArgumentError => e
      raise Thor::Error, "Invalid print option: #{e.message}"
    end

    # rubocop:disable Metrics/CyclomaticComplexity
    def print_options
      opts = {}

      assign_if_provided(opts, :background)
      assign_if_provided(opts, :orientation)
      opts[:pageRanges] = merged_options[:page_ranges] if merged_options[:page_ranges]

      if option_provided?(:scale)
        scale = merged_options[:scale]
        raise ArgumentError, "Scale must be between 0.1 and 2.0" unless (0.1..2.0).include?(scale)

        opts[:scale] = scale
      end

      assign_if_provided(opts, :shrinkToFit, :shrink_to_fit)

      # Margins
      margin_keys = {
        top: :margin_top,
        bottom: :margin_bottom,
        left: :margin_left,
        right: :margin_right
      }
      margins = {}
      margin_keys.each do |short, full|
        assign_if_provided(margins, short, full)
      end
      opts[:margin] = margins unless margins.empty?

      # Page size
      page = {}
      assign_if_provided(page, :width, :page_width)
      assign_if_provided(page, :height, :page_height)
      opts[:page] = page unless page.empty?

      opts.empty? ? nil : opts
    end

    # rubocop:enable Metrics/CyclomaticComplexity

    def option_provided?(key)
      ARGV.include?("--#{key.to_s.tr("_", "-")}") || ARGV.include?("--#{key}")
    end

    def assign_if_provided(hash, key, option_key = key)
      hash[key] = merged_options[option_key] if option_provided?(option_key)
    end

    def launcher
      # rubocop:disable Layout/BeginEndAlignment
      @launcher ||= begin
                      username, password = parse_auth(merged_options[:auth]) if merged_options[:auth]

                      Bidi2pdf::Launcher.new(
                        url: merged_options[:url],
                        output: merged_options[:output],
                        cookies: parse_key_values(merged_options[:cookie]),
                        headers: parse_key_values(merged_options[:header]),
                        auth: { username: username, password: password },
                        port: merged_options[:port],
                        remote_browser_url: merged_options[:remote_browser_url],
                        headless: merged_options[:headless],
                        wait_window_loaded: merged_options[:wait_window_loaded],
                        wait_network_idle: merged_options[:wait_network_idle],
                        print_options: print_options
                      )
                    end
      # rubocop:enable Layout/BeginEndAlignment
    end

    # rubocop:enable Metrics/AbcSize

    def configure
      Bidi2pdf.configure do |config|
        config.logger.level = log_level
        config.default_timeout = merged_options[:default_timeout]

        Chromedriver::Binary.configure do |c|
          c.logger.level = log_level
        end
      end
    end

    def log_level
      case merged_options[:log_level]
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

    def merged_options
      defaults = load_config || {}
      Thor::CoreExt::HashWithIndifferentAccess.new(defaults.merge(options))
    end
  end
end
