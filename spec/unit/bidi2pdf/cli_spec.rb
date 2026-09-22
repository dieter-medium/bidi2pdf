# frozen_string_literal: true

require "spec_helper"
require "bidi2pdf/cli"

# rubocop:disable-next  RSpec/AnyInstance
RSpec.describe Bidi2pdf::CLI do
  let(:cli_runner) { described_class.new }

  # Structured-mode commands call Kernel#exit explicitly, which would otherwise kill the rspec
  # process itself; this captures $stdout/$stderr around
  # the block and turns that exit into a plain return value instead of letting SystemExit propagate.
  def capture_streams
    original_stdout = $stdout
    original_stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    status = nil

    begin
      yield
    rescue SystemExit => e
      status = e.status
    end

    [status, $stdout.string, $stderr.string]
  ensure
    $stdout = original_stdout
    $stderr = original_stderr
    # perform_structured_render's own reserve_stdout_for_machine_output already reopened these back
    # to (what was, at that point) $stdout - which was still this example's StringIO. Reopen once
    # more now that the real $stdout is back, so a later example's ordinary logging doesn't
    # silently vanish into an orphaned StringIO.
    [Bidi2pdf.logger, Bidi2pdf.network_events_logger, Bidi2pdf.browser_console_logger].compact.each { |logger| logger.logger.reopen($stdout) }
  end

  describe "#render" do
    context "with required options only" do
      it "accepts --url and starts launcher" do
        allow_any_instance_of(Bidi2pdf::Launcher).to receive(:launch)
        allow_any_instance_of(Bidi2pdf::Launcher).to receive(:stop)

        expect do
          cli_runner.invoke(:render, [], { url: "http://localhost/test" })
        end.not_to raise_error
      end
    end

    context "when required option :url is missing" do
      it "raises a Thor::Error naming --html-file with a hyphen, matching every other user-facing mention" do
        expect do
          cli_runner.invoke(:render)
        end.to raise_error(Thor::Error, "Missing required option --url or --html-file needs to be specified")
      end
    end

    context "with --html-file" do
      it "passes it through to Launcher as inputfile (regression test for the historic :hmtl_file typo)" do
        html_file = fixture_file("sample.html")
        captured_inputfile = nil

        allow(Bidi2pdf::Launcher).to receive(:new) do |**kwargs|
          captured_inputfile = kwargs[:inputfile]
          instance_double(Bidi2pdf::Launcher, launch: nil, stop: nil)
        end

        cli_runner.invoke(:render, [], { html_file: html_file })

        expect(captured_inputfile).to eq(html_file)
      end
    end

    context "with print options and validation" do
      it "calls the print option validator" do
        allow_any_instance_of(Bidi2pdf::Launcher).to receive(:launch)
        allow_any_instance_of(Bidi2pdf::Launcher).to receive(:stop)

        validator = class_double(Bidi2pdf::Bidi::Commands::PrintParametersValidator, validate!: true)
        stub_const("Bidi2pdf::Bidi::Commands::PrintParametersValidator", validator)

        allow_any_instance_of(described_class).to receive(:option_provided?) do |_instance, key|
          %i[scale shrink_to_fit orientation].include?(key)
        end

        cli_runner.invoke(
          :render,
          [],
          {
            url: "http://localhost/test",
            orientation: "portrait",
            scale: 1.2,
            shrink_to_fit: false
          }
        )

        expect(validator).to have_received(:validate!).with(hash_including(:orientation, :scale, :shrinkToFit))
      end
    end

    describe "#version" do
      it "prints the current version" do
        expect do
          cli_runner.invoke(:version)
        end.to output(/bidi2pdf #{Regexp.escape(Bidi2pdf::VERSION)}/).to_stdout
      end

      it "prints a JSON document with --json" do
        status, stdout, = capture_streams { cli_runner.invoke(:version, [], json: true) }

        expect([status, JSON.parse(stdout)["bidi2pdf"]]).to eq([nil, Bidi2pdf::VERSION])
      end
    end

    describe "#schema" do
      it "prints the render schema" do
        status, stdout, = capture_streams { cli_runner.invoke(:schema, ["render"]) }

        expect([status, JSON.parse(stdout)]).to eq([nil, Bidi2pdf::Schema::RENDER])
      end

      it "prints the diagnose schema" do
        status, stdout, = capture_streams { cli_runner.invoke(:schema, ["diagnose"]) }

        expect([status, JSON.parse(stdout)]).to eq([nil, Bidi2pdf::Schema::DIAGNOSE])
      end

      it "prints the run schema" do
        status, stdout, = capture_streams { cli_runner.invoke(:schema, ["run"]) }

        expect([status, JSON.parse(stdout)]).to eq([nil, Bidi2pdf::Schema::RUN])
      end

      it "raises a Thor::Error for an unknown kind" do
        expect { cli_runner.invoke(:schema, ["bogus"]) }.to raise_error(Thor::Error, /Unknown schema 'bogus'/)
      end
    end

    context "with --json" do
      def stub_successful_launch(pdf_bytes: File.binread(fixture_file("sample.pdf")))
        allow(Bidi2pdf::Launcher).to receive(:new) do
          instance_double(Bidi2pdf::Launcher, stop: nil).tap do |double|
            allow(double).to receive(:launch) do
              Bidi2pdf.notification_service.instrument("print.bidi2pdf") { |payload| payload[:pdf_base64] = Base64.strict_encode64(pdf_bytes) }
            end
          end
        end
      end

      def stub_failing_launch(error)
        double = instance_double(Bidi2pdf::Launcher, stop: nil)
        allow(double).to receive(:launch).and_raise(error)
        allow(Bidi2pdf::Launcher).to receive(:new).and_return(double)
      end

      it "emits a single ok:true JSON document on stdout, and exits 0" do
        stub_successful_launch

        status, stdout, = capture_streams { cli_runner.invoke(:render, [], url: "http://localhost/test", json: true) }

        parsed = JSON.parse(stdout)
        expect([status, parsed["ok"], parsed["command"], parsed["schema_version"]]).to eq([0, true, "render", 1])
      end

      it "writes no human-readable logs to stdout" do
        stub_successful_launch

        _status, stdout, = capture_streams { cli_runner.invoke(:render, [], url: "http://localhost/test", json: true) }

        expect { JSON.parse(stdout) }.not_to raise_error
      end

      it "emits a structured, ok:false document and a non-zero exit when the render fails" do
        stub_failing_launch(Bidi2pdf::NavigationTimeoutError.new("Navigation did not complete within 60 seconds"))

        status, stdout, = capture_streams { cli_runner.invoke(:render, [], url: "http://localhost/test", json: true) }

        parsed = JSON.parse(stdout)
        expect([status, parsed["ok"], parsed["error"]["code"]]).to eq([3, false, "NAVIGATION_TIMEOUT"])
      end

      it "still produces valid JSON when neither --url nor --html-file was given" do
        status, stdout, = capture_streams { cli_runner.invoke(:render, [], json: true) }

        parsed = JSON.parse(stdout)
        expect([status, parsed["error"]["code"]]).to eq([2, "MISSING_INPUT"])
      end

      it "rejects --url and --html-file together" do
        status, stdout, = capture_streams { cli_runner.invoke(:render, [], url: "http://x", html_file: fixture_file("sample.html"), json: true) }

        expect([status, JSON.parse(stdout)["error"]["code"]]).to eq([2, "MULTIPLE_INPUT_SOURCES"])
      end

      # Regression test for finding #2: schema render's own properties must actually be what
      # render --json prints, not just a plausible-looking, independently-drifted shape.
      it "prints exactly the keys schema render declares" do
        stub_successful_launch

        _status, stdout, = capture_streams { cli_runner.invoke(:render, [], url: "http://localhost/test", json: true) }

        expect(JSON.parse(stdout).keys).to match_array(Bidi2pdf::Schema::RENDER["properties"].keys)
      end
    end

    context "with --json and --output - together" do
      # rubocop:disable-next RSpec/MultipleExpectations
      it "is rejected before any browser is launched, reported on stderr, exit 2" do
        allow(Bidi2pdf::Launcher).to receive(:new)

        status, _stdout, stderr = capture_streams { cli_runner.invoke(:render, [], url: "http://x", json: true, output: "-") }

        expect([status, JSON.parse(stderr)["error"]["code"]]).to eq([2, "INVALID_CONFIG"])
        expect(Bidi2pdf::Launcher).not_to have_received(:new)
      end
    end

    context "with --output -" do
      def stub_successful_launch(pdf_bytes:)
        allow(Bidi2pdf::Launcher).to receive(:new) do
          instance_double(Bidi2pdf::Launcher, stop: nil).tap do |double|
            allow(double).to receive(:launch) do
              Bidi2pdf.notification_service.instrument("print.bidi2pdf") { |payload| payload[:pdf_base64] = Base64.strict_encode64(pdf_bytes) }
            end
          end
        end
      end

      it "writes the raw PDF bytes to stdout, nothing else" do
        pdf_bytes = File.binread(fixture_file("sample.pdf"))
        stub_successful_launch(pdf_bytes: pdf_bytes)

        _status, stdout, = capture_streams { cli_runner.invoke(:render, [], url: "http://localhost/test", output: "-") }

        expect(stdout.b).to eq(pdf_bytes)
      end
    end

    context "with --stdin" do
      it "renders the piped HTML by writing it to a tempfile passed as inputfile" do
        # The tempfile is unlinked in perform_structured_render's own ensure once launch returns,
        # so its content has to be captured from inside the stub, while it still exists on disk.
        captured_content = nil
        allow(Bidi2pdf::Launcher).to receive(:new) do |**kwargs|
          captured_content = File.read(kwargs[:inputfile])
          instance_double(Bidi2pdf::Launcher, launch: nil, stop: nil)
        end
        allow($stdin).to receive(:read).and_return("<html><body>hi</body></html>")

        capture_streams { cli_runner.invoke(:render, [], stdin: true, json: true) }

        expect(captured_content).to eq("<html><body>hi</body></html>")
      end

      it "reports EMPTY_INPUT for blank stdin" do
        allow($stdin).to receive(:read).and_return("   \n")

        status, stdout, = capture_streams { cli_runner.invoke(:render, [], stdin: true, json: true) }

        expect([status, JSON.parse(stdout)["error"]["code"]]).to eq([2, "EMPTY_INPUT"])
      end
    end

    context "with --manifest" do
      def stub_successful_launch
        allow(Bidi2pdf::Launcher).to receive(:new) do
          instance_double(Bidi2pdf::Launcher, stop: nil).tap do |double|
            allow(double).to receive(:launch) do
              pdf_bytes = File.binread(fixture_file("sample.pdf"))
              Bidi2pdf.notification_service.instrument("print.bidi2pdf") { |payload| payload[:pdf_base64] = Base64.strict_encode64(pdf_bytes) }
            end
          end
        end
      end

      it "writes a manifest document with the documented top-level shape" do
        stub_successful_launch
        manifest_path = tmp_file("manifest-#{SecureRandom.hex(4)}.json")

        capture_streams { cli_runner.invoke(:render, [], url: "http://localhost/test", json: true, manifest: manifest_path) }

        manifest = JSON.parse(File.read(manifest_path))
        expect(manifest.values_at("schema_version", "bidi2pdf_version", "input")).to eq([1, Bidi2pdf::VERSION, { "type" => "url", "url" => "http://localhost/test" }])
      ensure
        File.delete(manifest_path) if manifest_path && File.exist?(manifest_path)
      end
    end

    context "with the diagnose command" do
      let(:tab) { instance_double(Bidi2pdf::Bidi::BrowserTab, execute_script: { "type" => "success", "result" => { "type" => "string", "value" => "{}" } }) }

      def stub_diagnose_launcher
        allow(Bidi2pdf::Launcher).to receive(:new).and_return(instance_double(Bidi2pdf::Launcher, diagnose: tab, stop: nil))
      end

      it "prints a JSON document with the diagnose shape under --json" do
        stub_diagnose_launcher

        status, stdout, = capture_streams { cli_runner.invoke(:diagnose, [], url: "http://localhost/test", json: true) }

        parsed = JSON.parse(stdout)
        expect([status, parsed["ok"], parsed["command"]]).to eq([0, true, "diagnose"])
      end

      it "includes the fonts/print_media/paged_js sections Diagnose collected" do
        stub_diagnose_launcher

        _status, stdout, = capture_streams { cli_runner.invoke(:diagnose, [], url: "http://localhost/test", json: true) }

        expect(JSON.parse(stdout).values_at("page", "fonts", "print_media", "paged_js")).to eq([{}, {}, {}, {}])
      end

      # rubocop:disable-next RSpec/MultipleExpectations
      it "captures a screenshot when --screenshot is given" do
        stub_diagnose_launcher
        allow(tab).to receive(:screenshot)

        _status, stdout, = capture_streams { cli_runner.invoke(:diagnose, [], url: "http://localhost/test", json: true, screenshot: "out.png") }

        expect(tab).to have_received(:screenshot).with("out.png")
        expect(JSON.parse(stdout)["screenshot"]).to eq("out.png")
      end

      it "prints a human-readable summary without --json" do
        stub_diagnose_launcher

        status, stdout, = capture_streams { cli_runner.invoke(:diagnose, [], url: "http://localhost/test") }

        expect([status, JSON.parse(stdout)["page"]]).to eq([nil, {}])
      end

      it "reports MISSING_INPUT when neither --url nor --html-file was given" do
        stub_diagnose_launcher

        status, stdout, = capture_streams { cli_runner.invoke(:diagnose, [], json: true) }

        expect([status, JSON.parse(stdout)["error"]["code"]]).to eq([2, "MISSING_INPUT"])
      end

      # Regression test for finding #2: schema diagnose's own properties must actually be what
      # diagnose --json prints, not the render schema's shape (they used to share one schema).
      it "prints exactly the keys schema diagnose declares" do
        stub_diagnose_launcher

        _status, stdout, = capture_streams { cli_runner.invoke(:diagnose, [], url: "http://localhost/test", json: true) }

        expect(JSON.parse(stdout).keys).to match_array(Bidi2pdf::Schema::DIAGNOSE["properties"].keys)
      end
    end

    context "with --json-stream" do
      def stub_successful_launch
        allow(Bidi2pdf::Launcher).to receive(:new) do
          instance_double(Bidi2pdf::Launcher, stop: nil).tap do |double|
            allow(double).to receive(:launch) do
              Bidi2pdf.notification_service.instrument("navigate_to.bidi2pdf", url: "http://localhost/test")
              pdf_bytes = File.binread(fixture_file("sample.pdf"))
              Bidi2pdf.notification_service.instrument("print.bidi2pdf") { |payload| payload[:pdf_base64] = Base64.strict_encode64(pdf_bytes) }
            end
          end
        end
      end

      it "streams one JSON event per stderr line, ending with the final result" do
        stub_successful_launch

        _status, _stdout, stderr = capture_streams { cli_runner.invoke(:render, [], url: "http://localhost/test", json: true, json_stream: true) }

        events = stderr.each_line.map { |line| JSON.parse(line) }
        expect([events.first["event"], events.last["event"], events.last["result"]["ok"]]).to eq(["navigate", "result", true])
      end

      # Regression test for finding #3: --json-stream used to silently do nothing without --json,
      # because only perform_structured_render ever built a JsonSubscriber. Human mode doesn't
      # redirect Bidi2pdf.logger (that's reserve_stdout_for_machine_output's own job, structured-
      # mode only), so this only asserts on the stream itself, not on stdout's log content.
      # rubocop:disable-next RSpec/MultipleExpectations
      it "also streams progress events without --json" do
        stub_successful_launch

        status, _stdout, stderr = capture_streams { cli_runner.invoke(:render, [], url: "http://localhost/test", json_stream: true) }
        events = stderr.each_line.map { |line| JSON.parse(line) }

        expect([status, events.first["event"]]).to eq([nil, "navigate"])
        # human mode builds no Result/payload to report, so unlike structured mode there is no
        # trailing {"event":"result",...} line here - see perform_human_render's own comment.
        expect(events.map { |e| e["event"] }).not_to include("result")
      end
    end
  end

  describe "run" do
    def write_recipe(yaml)
      path = tmp_file("cli-run-recipe-#{SecureRandom.hex(4)}.yml")
      File.write(path, yaml)
      path
    end

    let(:tab) { instance_double(Bidi2pdf::Bidi::BrowserTab, execute_script: { "type" => "success", "result" => { "type" => "boolean", "value" => true } }) }

    def stub_run_launcher
      allow(Bidi2pdf::Launcher).to receive(:new).and_return(instance_double(Bidi2pdf::Launcher, diagnose: tab, stop: nil))
    end

    context "with --validate" do
      # rubocop:disable-next RSpec/MultipleExpectations
      it "reports a valid recipe without launching a browser, human mode" do
        allow(Bidi2pdf::Launcher).to receive(:new)
        recipe = write_recipe("version: 1\nsource:\n  url: https://example.com\noutput:\n  manifest: out.json\n")

        status, stdout, = capture_streams { cli_runner.invoke(:run_recipe, [recipe], validate: true) }

        expect([status, stdout, Bidi2pdf::Launcher]).to eq([nil, "Recipe '#{recipe}' is valid.\n", Bidi2pdf::Launcher])
        expect(Bidi2pdf::Launcher).not_to have_received(:new)
      end

      it "reports a valid recipe as JSON, exit 0" do
        recipe = write_recipe("version: 1\nsource:\n  url: https://example.com\noutput:\n  manifest: out.json\n")

        status, stdout, = capture_streams { cli_runner.invoke(:run_recipe, [recipe], validate: true, json: true) }

        expect([status, JSON.parse(stdout)["ok"]]).to eq([0, true])
      end

      it "raises a Thor::Error for an invalid recipe in human mode" do
        recipe = write_recipe("version: 2\nsource:\n  url: https://example.com\noutput:\n  manifest: out.json\n")

        expect { cli_runner.invoke(:run_recipe, [recipe]) }.to raise_error(Thor::Error, /version must be 1/)
      end

      # rubocop:disable-next RSpec/MultipleExpectations
      it "reports an invalid recipe as a structured error, exit 2, without launching a browser" do
        allow(Bidi2pdf::Launcher).to receive(:new)
        recipe = write_recipe("version: 1\nsource:\n  url: https://example.com\n  file: x.html\noutput:\n  manifest: out.json\n")

        status, stdout, = capture_streams { cli_runner.invoke(:run_recipe, [recipe], json: true) }

        expect([status, JSON.parse(stdout)["error"]["code"]]).to eq([2, "INVALID_RECIPE"])
        expect(Bidi2pdf::Launcher).not_to have_received(:new)
      end
    end

    context "when running for real" do
      it "runs actions and assertions, exits 0, with the recipe result shape" do
        stub_run_launcher
        recipe = write_recipe(<<~YAML)
          version: 1
          source:
            url: https://example.com
          assert:
            - selector_exists:
                selector: "#total"
          output:
            manifest: #{tmp_file("cli-run-manifest-#{SecureRandom.hex(4)}.json")}
        YAML

        status, stdout, = capture_streams { cli_runner.invoke(:run_recipe, [recipe], json: true) }
        parsed = JSON.parse(stdout)

        expect([status, parsed["ok"], parsed["command"], parsed["assertions"].first["ok"]]).to eq([0, true, "run", true])
      end

      # Regression test for finding #2: schema run's own properties must actually be what
      # run --json prints, not the render schema's shape (they used to share one schema).
      it "prints exactly the keys schema run declares" do
        stub_run_launcher
        recipe = write_recipe(<<~YAML)
          version: 1
          source:
            url: https://example.com
          output:
            manifest: #{tmp_file("cli-run-manifest-#{SecureRandom.hex(4)}.json")}
        YAML

        _status, stdout, = capture_streams { cli_runner.invoke(:run_recipe, [recipe], json: true) }

        expect(JSON.parse(stdout).keys).to match_array(Bidi2pdf::Schema::RUN["properties"].keys)
      end

      it "writes the manifest file when the run succeeds" do
        stub_run_launcher
        manifest_path = tmp_file("cli-run-manifest-#{SecureRandom.hex(4)}.json")
        recipe = write_recipe(<<~YAML)
          version: 1
          source:
            url: https://example.com
          output:
            manifest: #{manifest_path}
        YAML

        capture_streams { cli_runner.invoke(:run_recipe, [recipe], json: true) }

        expect(JSON.parse(File.read(manifest_path))["input"]).to eq("type" => "url", "url" => "https://example.com")
      ensure
        File.delete(manifest_path) if manifest_path && File.exist?(manifest_path)
      end

      it "stops at the first failing assertion and reports PAGE_NOT_AS_EXPECTED with a non-zero exit" do
        allow(tab).to receive(:execute_script).and_return({ "type" => "success", "result" => { "type" => "boolean", "value" => false } })
        stub_run_launcher
        recipe = write_recipe(<<~YAML)
          version: 1
          source:
            url: https://example.com
          assert:
            - selector_exists:
                selector: "#total"
          output:
            manifest: #{tmp_file("cli-run-manifest-#{SecureRandom.hex(4)}.json")}
        YAML

        status, stdout, = capture_streams { cli_runner.invoke(:run_recipe, [recipe], json: true) }
        parsed = JSON.parse(stdout)

        expect([status, parsed["ok"], parsed["error"]["code"], parsed["output"]]).to eq([4, false, "PAGE_NOT_AS_EXPECTED", nil])
      end

      it "prints actions/assertions/assigned as pretty JSON in human mode" do
        stub_run_launcher
        recipe = write_recipe(<<~YAML)
          version: 1
          source:
            url: https://example.com
          assert:
            - selector_exists:
                selector: "#total"
          output:
            manifest: #{tmp_file("cli-run-manifest-#{SecureRandom.hex(4)}.json")}
        YAML

        status, stdout, = capture_streams { cli_runner.invoke(:run_recipe, [recipe]) }

        expect([status, JSON.parse(stdout)["assertions"].first["ok"]]).to eq([nil, true])
      end
    end
  end
end
