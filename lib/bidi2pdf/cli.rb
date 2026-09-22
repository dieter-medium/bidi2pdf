# frozen_string_literal: true

require "thor"
require "yaml"
require "tempfile"

require_relative "cli/json_output"

module Bidi2pdf
  # rubocop:disable Metrics/AbcSize
  class CLI < Thor
    include JsonOutput

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
    # of course, it's possible to render a local file via: --url file:///path/to/the/file.html
    # but this should showcase the scenario that you render a string within ruby as pdf without the need
    # to store it on disc
    option :html_file, desc: "The local HTML file to render"
    option :output, default: "output.pdf", desc: "Filename for the output PDF", aliases: "-o"
    option :cookie, type: :array, default: [], banner: "name=value", desc: "One or more cookies", aliases: "-C"
    option :header, type: :array, default: [], banner: "name=value", desc: "One or more custom headers", aliases: "-H"
    option :auth, type: :string, banner: "user:pass", desc: "Basic auth credentials", aliases: "-a"
    option :headless, type: :boolean, default: true, desc: "Run Chrome in headless mode"
    option :no_sandbox, type: :boolean, default: false, desc: "Disable Chrome sandbox (needed inside containers)"
    option :chrome_flag, type: :array, default: [], banner: "--flag[=value]", desc: "Extra Chrome flags appended to defaults", aliases: "--cf"
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
    verbosity_levels = Bidi2pdf::VerboseLogger::VERBOSITY_LEVELS.keys.sort_by { |k| Bidi2pdf::VerboseLogger::VERBOSITY_LEVELS[k] }
    option :verbosity,
           type: :string,
           default: verbosity_levels.first, enum: Bidi2pdf::VerboseLogger::VERBOSITY_LEVELS.keys.sort_by { |k| Bidi2pdf::VerboseLogger::VERBOSITY_LEVELS[k] }.map(&:to_s),
           desc: "Set debug verbosity level", aliases: "-v"
    option :log_network_traffic, type: :boolean, default: false, desc: "Log network traffic", aliases: "-n"
    option :network_log_format,
           type: :string,
           default: "console",
           enum: %w[console pdf],
           desc: "Choose network log format: console or pdf", aliases: "-f"

    option :json, type: :boolean, default: false, desc: "Emit a single structured JSON result document (see `bidi2pdf schema render`) instead of human-readable logs"
    option :json_stream, type: :boolean, default: false, desc: "Emit one JSON progress event per line to stderr as the render happens, with or without --json (see `bidi2pdf schema event`)"
    option :stdin, type: :boolean, default: false, desc: "Read the HTML document to render from stdin, instead of --url/--html-file"
    option :manifest, type: :string, desc: "Write a render manifest (see `bidi2pdf schema manifest`) to this file"

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
    option :generate_tagged_pdf, type: :boolean, default: false, desc: "Generate tagged PDF"
    option :generate_document_outline, type: :boolean, default: false, desc: "Generate document outline"

    class << self
      def exit_on_failure?
        true
      end
    end

    def render
      load_config

      if json_mode? && stdout_output?
        reject_conflicting_output_streams!
        return
      end

      json_mode? || stdout_output? ? perform_structured_render : perform_human_render
    end

    desc "version", "Show bidi2pdf version"
    option :json, type: :boolean, default: false, desc: "Emit version info as JSON instead of a plain string"

    def version
      if options[:json]
        puts version_info.to_json
      else
        puts "bidi2pdf #{Bidi2pdf::VERSION}"
      end
    end

    desc "schema KIND", "Print the JSON Schema for KIND (render, diagnose, run, manifest, recipe, event)"

    def schema(kind)
      puts JSON.pretty_generate(Bidi2pdf::Schema.for(kind))
    rescue ArgumentError => e
      raise Thor::Error, e.message
    end

    desc "diagnose", "Load a page and report render-focused diagnostics (console, network, fonts, print CSS, Paged.js) without producing a PDF"
    option :url, desc: "The URL to load"
    option :html_file, desc: "The local HTML file to load"
    option :stdin, type: :boolean, default: false, desc: "Read the HTML document to load from stdin, instead of --url/--html-file"
    option :cookie, type: :array, default: [], banner: "name=value", desc: "One or more cookies", aliases: "-C"
    option :header, type: :array, default: [], banner: "name=value", desc: "One or more custom headers", aliases: "-H"
    option :auth, type: :string, banner: "user:pass", desc: "Basic auth credentials", aliases: "-a"
    option :headless, type: :boolean, default: true, desc: "Run Chrome in headless mode"
    option :no_sandbox, type: :boolean, default: false, desc: "Disable Chrome sandbox (needed inside containers)"
    option :chrome_flag, type: :array, default: [], banner: "--flag[=value]", desc: "Extra Chrome flags appended to defaults", aliases: "--cf"
    option :port, type: :numeric, default: 0, desc: "Port to run ChromeDriver on (0 = auto)"
    option :wait_window_loaded, type: :boolean, default: false, desc: "Wait for the window to be fully loaded"
    option :wait_network_idle, type: :boolean, default: false, desc: "Wait for network to be idle"
    option :default_timeout, type: :numeric, default: 60, desc: "Default timeout for commands"
    option :remote_browser_url, type: :string, desc: "Remote browser URL for ChromeDriver"
    option :log_level, type: :string, default: "info", enum: %w[debug info warn error fatal unknown], desc: "Set log level"
    option :verbosity,
           type: :string,
           default: Bidi2pdf::VerboseLogger::VERBOSITY_LEVELS.keys.min_by { |k| Bidi2pdf::VerboseLogger::VERBOSITY_LEVELS[k] }.to_s,
           enum: Bidi2pdf::VerboseLogger::VERBOSITY_LEVELS.keys.map(&:to_s),
           desc: "Set debug verbosity level", aliases: "-v"
    option :log_network_traffic, type: :boolean, default: false, desc: "Log network traffic", aliases: "-n"
    option :json, type: :boolean, default: false, desc: "Emit a single structured JSON document (see `bidi2pdf schema diagnose`) instead of a human-readable summary"
    option :json_stream, type: :boolean, default: false, desc: "Emit one JSON progress event per line to stderr as diagnostics run, with or without --json (see `bidi2pdf schema event`)"
    option :screenshot, type: :string, desc: "Also capture a screenshot to this PNG file"
    option :pdf, type: :string, desc: "Also render a PDF to this file and report its page count / blank-check"

    def diagnose
      load_config

      json_mode? ? perform_structured_diagnose : perform_human_diagnose
    end

    desc "run RECIPE", "Run a declarative recipe (see `bidi2pdf schema recipe`)"
    option :validate, type: :boolean, default: false, desc: "Validate the recipe and exit, without launching a browser"
    option :json, type: :boolean, default: false, desc: "Emit a single structured JSON result document (see `bidi2pdf schema run`) instead of a human-readable summary"
    option :json_stream, type: :boolean, default: false, desc: "Emit one JSON progress event per line to stderr as the recipe runs, with or without --json (see `bidi2pdf schema event`)"
    option :headless, type: :boolean, desc: "Override the recipe's browser.headless"
    option :remote_browser_url, type: :string, desc: "Remote browser URL for ChromeDriver"
    option :default_timeout, type: :numeric, default: 60, desc: "Default timeout for commands"
    option :log_level, type: :string, default: "info", enum: %w[debug info warn error fatal unknown], desc: "Set log level"
    option :verbosity,
           type: :string,
           default: Bidi2pdf::VerboseLogger::VERBOSITY_LEVELS.keys.min_by { |k| Bidi2pdf::VerboseLogger::VERBOSITY_LEVELS[k] }.to_s,
           enum: Bidi2pdf::VerboseLogger::VERBOSITY_LEVELS.keys.map(&:to_s),
           desc: "Set debug verbosity level", aliases: "-v"
    option :log_network_traffic, type: :boolean, default: false, desc: "Log network traffic", aliases: "-n"

    # Named run_recipe, not run: Thor::Base reserves "run" as a method name (Thor::Base::
    # ClassMethods#is_thor_reserved_word?) and refuses to define a command with that name. `map`
    # below is what makes `bidi2pdf run recipe.yml` dispatch here.
    def run_recipe(recipe_path)
      load_config

      json_mode? ? perform_structured_run(recipe_path) : perform_human_run(recipe_path)
    end
    map "run" => :run_recipe

    desc "template", "Generate a config file template"
    option :output, default: "bidi2pdf.yml", desc: "Output configuration filename"

    def template
      config = {
        "url" => "https://example.com",
        "output" => "output.pdf",
        "headless" => true,
        "no_sandbox" => false,
        "chrome_flag" => [],
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

    # --- render: human mode (default) - unchanged behavior, just wrapping the new typed errors
    # validate_required_options!/validate_print_options now raise back into the historic
    # Thor::Error type/message pair, so every previously-documented CLI behavior stays intact.

    # rubocop:disable-next Metrics/CyclomaticComplexity
    def perform_human_render
      # --json-stream works standalone, independent of --json: progress events go to stderr while
      # human-readable output keeps using stdout as always. There is no synthetic final "result"
      # event here - human mode
      # builds no Result/payload to report, and the human-readable log itself is the completion/
      # failure signal; see Notifications::JsonSubscriber's own #emit_result, never called here.
      stream = Notifications::JsonSubscriber.new if json_stream?

      validate_required_options!
      configure

      Bidi2pdf.logger.info "Rendering: #{requested_source_description} -> #{merged_options[:output]}"
      Bidi2pdf.logger.info "Print options: #{print_options.inspect}" if print_options

      validate_print_options(print_options) if print_options

      launcher.launch
    rescue Bidi2pdf::Error => e
      raise Thor::Error, e.message
    ensure
      launcher.stop if defined?(@launcher) && @launcher
      stream&.unsubscribe
      cleanup_stdin_tempfile
    end

    # --- render: structured mode (--json and/or --output -). Every failure ends up as a Result
    # rather than a raised exception, so this method itself never raises; it always exits
    # explicitly instead.

    def perform_structured_render
      stream = Notifications::JsonSubscriber.new if json_stream?

      reserve_stdout_for_machine_output do
        configure

        collector = ResultCollector.new(requested_url: requested_source_description, command: "render", output: render_output_label)

        result = collector.around do
          validate_required_options!
          validate_print_options(print_options) if print_options
          launcher.launch
        end

        stream&.emit_result(result)
        write_manifest(result) if merged_options[:manifest]
        emit_structured_render_output(result, collector)

        exit_for_result(result)
      end
    ensure
      launcher.stop if defined?(@launcher) && @launcher
      stream&.unsubscribe
      cleanup_stdin_tempfile
    end

    def emit_structured_render_output(result, collector)
      if stdout_output?
        $stdout.write(collector.pdf_bytes || "")
      else
        $stdout.puts(result.to_json)
      end
    end

    # --- diagnose - reuses ResultCollector for console/network_failures/navigation exactly as
    # render does, but its own JSON shape (page, fonts, print_media, paged_js, screenshot, pdf)
    # rather than Result#to_h, since a page diagnostic and a render result are genuinely
    # different documents.

    def perform_human_diagnose
      # See perform_human_render's own comment: --json-stream works standalone here too.
      stream = Notifications::JsonSubscriber.new if json_stream?

      validate_required_options!
      configure

      tab = launcher.diagnose
      diagnostics = Diagnose.new(tab: tab).call
      diagnostics[:screenshot] = capture_diagnose_screenshot(tab)
      diagnostics[:pdf] = capture_diagnose_pdf(tab)

      puts JSON.pretty_generate(diagnostics.compact)
    rescue Bidi2pdf::Error => e
      raise Thor::Error, e.message
    ensure
      launcher.stop if defined?(@launcher) && @launcher
      stream&.unsubscribe
      cleanup_stdin_tempfile
    end

    def perform_structured_diagnose
      stream = Notifications::JsonSubscriber.new if json_stream?

      reserve_stdout_for_machine_output do
        configure

        collector = ResultCollector.new(requested_url: requested_source_description, command: "diagnose")
        diagnostics = {}

        result = collector.around do
          validate_required_options!
          tab = launcher.diagnose
          diagnostics.merge!(Diagnose.new(tab: tab).call)
          diagnostics[:screenshot] = capture_diagnose_screenshot(tab)
          diagnostics[:pdf] = capture_diagnose_pdf(tab)
        end

        stream&.emit_result(result)
        $stdout.puts(diagnose_payload(result, diagnostics).to_json)

        exit_for_result(result)
      end
    ensure
      launcher.stop if defined?(@launcher) && @launcher
      stream&.unsubscribe
      cleanup_stdin_tempfile
    end

    def diagnose_payload(result, diagnostics)
      {
        schema_version: 1,
        ok: result.ok?,
        command: "diagnose",
        page: diagnostics[:page],
        console: result.console,
        network_failures: result.network_failures,
        fonts: diagnostics[:fonts],
        print_media: diagnostics[:print_media],
        paged_js: diagnostics[:paged_js],
        screenshot: diagnostics[:screenshot],
        pdf: diagnostics[:pdf],
        warnings: result.warnings,
        error: result.error
      }
    end

    def capture_diagnose_screenshot(tab)
      return nil unless merged_options[:screenshot]

      tab.screenshot(merged_options[:screenshot])
      merged_options[:screenshot]
    end

    def capture_diagnose_pdf(tab)
      return nil unless merged_options[:pdf]

      bytes = nil
      tab.print(merged_options[:pdf]) { |pdf_base64| bytes = Base64.decode64(pdf_base64) }

      { path: merged_options[:pdf], pages: PdfInspection.page_count(bytes), not_blank: bytes ? !PdfInspection.text(bytes).to_s.strip.empty? : nil }
    end

    # --- run - Loader/Validator run before any browser work, both in --validate and in a real
    # run, so an invalid recipe never launches one.

    # rubocop:disable-next Metrics/CyclomaticComplexity
    def perform_human_run(recipe_path)
      recipe = load_and_validate_recipe(recipe_path)
      return puts "Recipe '#{recipe_path}' is valid." if merged_options[:validate]

      # See perform_human_render's own comment: --json-stream works standalone here too. Human
      # mode's own printed summary below is a subset of the full `run` schema shape (no
      # schema_version/ok/command/output/...), so - consistent with the other two human paths -
      # there is still no synthetic final "result" event; building the full shape here just for
      # that would duplicate perform_structured_run's own run_payload.
      stream = Notifications::JsonSubscriber.new if json_stream?

      configure
      state = {}
      action_entries = []
      assertion_entries = []
      collector = ResultCollector.new(requested_url: recipe_requested_url(recipe), command: "run")

      result = collector.around do
        with_recipe_tab(recipe) do |tab|
          runner = Recipe::Runner.new(recipe: recipe, tab: tab, collector: collector)
          run_recipe_steps(runner, :run_actions) { |entries| action_entries = entries }
          runner.pdf_bytes = print_for_recipe(tab, recipe) if recipe.needs_pdf?
          run_recipe_steps(runner, :run_assertions) { |entries| assertion_entries = entries }
          write_recipe_screenshot(tab, recipe)
          state = runner.state
        end
      end

      raise Thor::Error, result.error[:message] unless result.ok?

      puts JSON.pretty_generate(actions: action_entries, assertions: assertion_entries, assigned: state)
    rescue Bidi2pdf::Error => e
      raise Thor::Error, e.message
    ensure
      @run_launcher&.stop
      stream&.unsubscribe
      cleanup_stdin_tempfile
    end

    # rubocop:disable-next Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def perform_structured_run(recipe_path)
      recipe = load_and_validate_recipe(recipe_path)

      if merged_options[:validate]
        puts({ schema_version: 1, ok: true, command: "run", recipe: recipe_path }.to_json)
        exit(Bidi2pdf::ExitCodes::SUCCESS)
      end

      stream = Notifications::JsonSubscriber.new if json_stream?

      reserve_stdout_for_machine_output do
        configure

        collector = ResultCollector.new(requested_url: recipe_requested_url(recipe), command: "run", output: recipe.output["pdf"])
        state = {}
        action_entries = []
        assertion_entries = []

        result = collector.around do
          with_recipe_tab(recipe) do |tab|
            runner = Recipe::Runner.new(recipe: recipe, tab: tab, collector: collector)
            run_recipe_steps(runner, :run_actions) { |entries| action_entries = entries }
            runner.pdf_bytes = print_for_recipe(tab, recipe) if recipe.needs_pdf?
            run_recipe_steps(runner, :run_assertions) { |entries| assertion_entries = entries }
            write_recipe_screenshot(tab, recipe)
            state = runner.state
          end
        end

        write_recipe_manifest(recipe, result) if recipe.output["manifest"] && result.ok?

        payload = run_payload(recipe_path, recipe, result, action_entries, assertion_entries, state)
        stream&.emit_result(payload)
        $stdout.puts(payload.to_json)

        exit_for_result(result)
      end
    rescue Bidi2pdf::InvalidRecipeError, Bidi2pdf::PdfInspectionUnavailableError, Bidi2pdf::InvalidPrintOptionError => e
      $stdout.puts Bidi2pdf::Result.failure(command: "run", error: ErrorCodes.describe(e)).to_json
      exit(Bidi2pdf::ExitCodes.for(ErrorCodes.for(e)))
    ensure
      @run_launcher&.stop
      stream&.unsubscribe
      cleanup_stdin_tempfile
    end

    def load_and_validate_recipe(recipe_path)
      recipe = Bidi2pdf::Recipe.load(recipe_path)
      recipe.validate!
      recipe
    end

    def recipe_requested_url(recipe)
      recipe.source["url"] || recipe.source["file"] || "(stdin)"
    end

    def with_recipe_tab(recipe)
      @run_launcher = launcher_for_recipe(recipe)
      tab = @run_launcher.diagnose

      yield(tab)
    end

    # A failing action/assertion raises Recipe::Runner::StepFailure (its own entries plus the real
    # Bidi2pdf::Error as #cause). The block always receives the entries run so far - whether every
    # step succeeded or the run stopped partway - before the cause is re-raised so
    # ResultCollector's ordinary error handling takes over; without the block, a failure's partial
    # entries would otherwise be lost along with the exception that discarded them.
    def run_recipe_steps(runner, method_name)
      entries = runner.public_send(method_name)
      yield entries
      entries
    rescue Recipe::Runner::StepFailure => e
      yield e.entries
      raise e.cause
    end

    def launcher_for_recipe(recipe)
      headless = merged_options[:headless]
      headless = recipe.browser_options.fetch("headless", true) if headless.nil?

      Bidi2pdf::Launcher.new(
        url: recipe.source["url"],
        inputfile: recipe_input_path(recipe),
        output: nil,
        cookies: recipe.cookies,
        headers: recipe.headers,
        auth: (recipe.auth || {}).transform_keys(&:to_sym),
        port: 0,
        remote_browser_url: merged_options[:remote_browser_url],
        headless: headless,
        wait_window_loaded: false,
        wait_network_idle: false,
        print_options: {},
        network_log_format: "console"
      )
    end

    def recipe_input_path(recipe)
      source = recipe.source
      return nil if source["url"]
      return source["file"] if source["file"]
      return write_stdin_tempfile if source["stdin"]

      nil
    end

    def print_for_recipe(tab, recipe)
      bytes = nil
      tab.print(recipe.output["pdf"], print_options: symbolize_print_options(recipe.print_options)) { |pdf_base64| bytes = Base64.decode64(pdf_base64) }
      bytes
    end

    def symbolize_print_options(opts)
      opts.to_h { |key, value| [key.to_sym, value] }
    end

    def write_recipe_screenshot(tab, recipe)
      return unless recipe.output["screenshot"]

      tab.screenshot(recipe.output["screenshot"])
    end

    def write_recipe_manifest(recipe, result)
      Manifest.new(
        result: result,
        input: { type: recipe_input_type(recipe), url: recipe.source["url"] || recipe.source["file"] },
        headers: recipe.headers,
        browser: { browser_name: "chrome", headless: merged_options[:headless] }
      ).tap { |manifest| File.write(recipe.output["manifest"], "#{manifest.to_json}\n") }
    end

    def recipe_input_type(recipe)
      return "url" if recipe.source["url"]
      return "html_file" if recipe.source["file"]

      "stdin"
    end

    def run_payload(recipe_path, recipe, result, action_entries, assertion_entries, state)
      {
        schema_version: 1,
        ok: result.ok?,
        command: "run",
        recipe: recipe_path,
        actions: action_entries,
        assertions: assertion_entries,
        assigned: state,
        output: result.ok? ? recipe_output_summary(recipe, result) : nil,
        duration_ms: result.duration_ms,
        warnings: result.warnings,
        error: result.error
      }
    end

    def recipe_output_summary(recipe, result)
      { pdf: recipe.output["pdf"], manifest: recipe.output["manifest"], screenshot: recipe.output["screenshot"], bytes: result.bytes, sha256: result.sha256,
        pages: result.pages }.compact
    end

    # --json and --output - both need exclusive use of stdout - rejected before anything else
    # runs, so neither stream is touched. The rejection
    # itself is reported on stderr, since stdout's meaning is exactly what is in dispute.
    def reject_conflicting_output_streams!
      error = Bidi2pdf::InvalidConfigError.new("--json and --output - cannot be used together")
      warn Bidi2pdf::Result.failure(command: "render", error: ErrorCodes.describe(error)).to_json
      exit(Bidi2pdf::ExitCodes.for("INVALID_CONFIG"))
    end

    def json_mode? = merged_options[:json]

    def json_stream? = merged_options[:json_stream]

    def stdin_mode? = merged_options[:stdin]

    def stdout_output? = merged_options[:output] == "-"

    def render_output_label = stdout_output? ? "-" : merged_options[:output]

    def render_output_path = stdout_output? ? nil : merged_options[:output]

    def requested_source_description
      merged_options[:url] || merged_options[:html_file] || "(stdin)"
    end

    def write_manifest(result)
      manifest = Manifest.new(
        result: result,
        input: { type: input_type, url: requested_source_description },
        headers: parse_key_values(merged_options[:header]),
        navigation_duration_ms: nil,
        browser: { browser_name: "chrome", headless: merged_options[:headless] }
      )

      File.write(merged_options[:manifest], "#{manifest.to_json}\n")
    rescue SystemCallError => e
      raise Bidi2pdf::OutputWriteError, "Could not write manifest '#{merged_options[:manifest]}': #{e.message}"
    end

    def input_type
      return "url" if merged_options[:url]
      return "html_file" if merged_options[:html_file]

      "stdin"
    end

    # --- input sources: --url / --html-file / --stdin are mutually exclusive. #render_input_path
    # is what actually reaches Launcher: for --stdin it is a Tempfile (cleaned up in the render
    # methods' own ensure) holding the piped content, reusing the exact same --html-file code
    # path rather than adding a second one.

    def load_config
      return unless options[:config] && File.exist?(options[:config])

      YAML.load_file(options[:config]).transform_keys(&:to_sym)
    end

    def input_sources_provided
      sources = []
      sources << :url if merged_options[:url]
      sources << :html_file if merged_options[:html_file]
      sources << :stdin if stdin_mode?
      sources
    end

    def validate_required_options!
      provided = input_sources_provided

      if provided.empty?
        raise Bidi2pdf::MissingInputError, "Missing required option --url or --html-file needs to be specified"
      elsif provided.size > 1
        raise Bidi2pdf::MultipleInputSourcesError, "Only one of --url, --html-file, --stdin may be given (got: #{provided.join(", ")})"
      elsif merged_options[:html_file] && !File.readable?(merged_options[:html_file])
        raise Bidi2pdf::InvalidConfigError, "HTML file '#{merged_options[:html_file]}' not found or not readable"
      end
    end

    def render_input_path
      return @render_input_path if defined?(@render_input_path)

      @render_input_path = stdin_mode? ? write_stdin_tempfile : merged_options[:html_file]
    end

    def stdin_content
      @stdin_content ||= $stdin.read.to_s
    end

    def write_stdin_tempfile
      raise Bidi2pdf::EmptyInputError, "No HTML was provided on stdin" if stdin_content.strip.empty?

      @stdin_tempfile = Tempfile.new(["bidi2pdf-stdin", ".html"])
      @stdin_tempfile.write(stdin_content)
      @stdin_tempfile.flush
      @stdin_tempfile.path
    end

    def cleanup_stdin_tempfile
      return unless @stdin_tempfile

      @stdin_tempfile.close
      @stdin_tempfile.unlink
      @stdin_tempfile = nil
    end

    def version_info
      {
        schema_version: 1,
        ok: true,
        command: "version",
        bidi2pdf: Bidi2pdf::VERSION,
        ruby: RUBY_VERSION,
        pdf_reader: pdf_reader_version
      }
    end

    def pdf_reader_version
      return nil unless Bidi2pdf::PdfInspection.available?

      Gem.loaded_specs["pdf-reader"]&.version&.to_s
    end

    def validate_print_options(opts)
      Bidi2pdf::Bidi::Commands::PrintParametersValidator.validate!(opts)
    rescue ArgumentError => e
      raise Bidi2pdf::InvalidPrintOptionError, "Invalid print option: #{e.message}"
    end

    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
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

      assign_if_provided(opts, :generate_tagged_pdf)
      assign_if_provided(opts, :generate_document_outline)

      opts[:cmd_type] = :cdp if opts[:generate_tagged_pdf] || opts[:generate_document_outline]

      opts.empty? ? nil : opts
    end

    # rubocop:enable Metrics/CyclomaticComplexity,  Metrics/PerceivedComplexity

    def option_provided?(key)
      ARGV.include?("--#{key.to_s.tr("_", "-")}") || ARGV.include?("--#{key}")
    end

    def assign_if_provided(hash, key, option_key = key)
      hash[key] = merged_options[option_key] if option_provided?(option_key)
    end

    def launcher
      @launcher ||= begin
                      username, password = parse_auth(merged_options[:auth]) if merged_options[:auth]

                      chrome_args = Bidi2pdf::Bidi::Session::DEFAULT_CHROME_ARGS.dup
                      no_sandbox = merged_options[:no_sandbox] || ENV["DISABLE_CHROME_SANDBOX"] == "true"
                      chrome_args << "--no-sandbox" if no_sandbox
                      chrome_args.concat(Array(merged_options[:chrome_flag]))

                      Bidi2pdf::Launcher.new(
                        url: merged_options[:url],
                        inputfile: render_input_path,
                        output: render_output_path,
                        cookies: parse_key_values(merged_options[:cookie]),
                        headers: parse_key_values(merged_options[:header]),
                        auth: { username: username, password: password },
                        port: merged_options[:port],
                        remote_browser_url: merged_options[:remote_browser_url],
                        headless: merged_options[:headless],
                        wait_window_loaded: merged_options[:wait_window_loaded],
                        wait_network_idle: merged_options[:wait_network_idle],
                        print_options: print_options,
                        network_log_format: merged_options[:network_log_format],
                        chrome_args: chrome_args
                      )
                    end
    end

    def configure
      Bidi2pdf.configure do |config|
        config.logger.level = log_level

        config.logger.verbosity = merged_options[:verbosity]

        config.network_events_logger.level = Logger::INFO if merged_options[:log_network_traffic]

        config.default_timeout = merged_options[:default_timeout]

        Chromedriver::Binary.configure do |c|
          c.logger.level = log_level
        end
      end
    end

    # rubocop: enable Metrics/MethodLength

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
# rubocop:enable Metrics/AbcSize
