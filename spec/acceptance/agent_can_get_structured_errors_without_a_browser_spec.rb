# frozen_string_literal: true

require "spec_helper"
require "open3"
require "json"

# Same real-subprocess boundary as agent_can_discover_the_json_schemas_spec.rb - see its header
# comment. These scenarios cover input mistakes an agent can make that are caught before any
# browser launches, so they're verifiable here even though rendering itself needs a real browser
# this sandbox doesn't have (see CLAUDE.md's "Verification limits").
RSpec.feature "As an LLM agent, I want a structured, parseable error instead of a crash when my input is wrong", :acceptance do
  # See agent_can_discover_the_json_schemas_spec.rb's own comment on this method: no "bundle",
  # "exec" prefix - this process already runs under bundle exec, and re-wrapping breaks the outer
  # bundle wrapper's own exit status even though the wrapped command's stdout/stderr stay correct.
  def bidi2pdf(*)
    exe = File.expand_path("../../exe/bidi2pdf", __dir__)
    root = File.expand_path("../..", __dir__)
    out, err, status = Open3.capture3(exe, *, chdir: root)
    [status.exitstatus, out, err]
  end

  scenario "Forgetting to say where the HTML comes from" do
    when_ "I call render --json without --url, --html-file, or --stdin" do
      before { @status, @stdout, = bidi2pdf("render", "--json") }

      then_ "I get a non-zero exit" do
        expect(@status).to eq(2)
      end

      and_ "I get a MISSING_INPUT code I can branch on, not a Ruby backtrace" do
        parsed = JSON.parse(@stdout)

        expect([parsed["ok"], parsed["error"]["code"]]).to eq([false, "MISSING_INPUT"])
      end

      and_ "the response still matches schema render's own required keys" do
        expect(JSON.parse(@stdout).keys).to match_array(Bidi2pdf::Schema::RENDER["properties"].keys)
      end
    end
  end

  scenario "Giving two input sources at once" do
    when_ "I call render --json with both --url and --html-file" do
      before { @status, @stdout, = bidi2pdf("render", "--json", "--url", "https://example.com", "--html-file", "/nonexistent.html") }

      then_ "I get a non-zero exit before any browser is touched" do
        expect(@status).to eq(2)
      end

      and_ "I get MULTIPLE_INPUT_SOURCES, not a confusing partial render" do
        expect(JSON.parse(@stdout)["error"]["code"]).to eq("MULTIPLE_INPUT_SOURCES")
      end
    end
  end

  scenario "Pointing --html-file at a file that isn't there" do
    when_ "I call render --json with an --html-file that doesn't exist" do
      before { @status, @stdout, = bidi2pdf("render", "--json", "--html-file", "/definitely/not/a/real/file.html") }

      then_ "I get a non-zero exit" do
        expect(@status).to eq(2)
      end

      and_ "I get INVALID_CONFIG naming the bad path, not a filesystem exception" do
        parsed = JSON.parse(@stdout)

        expect([parsed["error"]["code"], parsed["error"]["message"]]).to eq(["INVALID_CONFIG", "HTML file '/definitely/not/a/real/file.html' not found or not readable"])
      end
    end
  end

  scenario "Asking for --json and --output - together" do
    when_ "I call render with both --json and --output -" do
      # Unlike every other scenario in this file, this rejection happens before
      # reserve_stdout_for_machine_output ever runs - --output - itself wants stdout for raw PDF
      # bytes, so the conflict error goes to stderr instead, keeping stdout empty and safe to pipe
      # into a PDF file even in this specific failure case. Confirmed live, not assumed.
      before { @status, @stdout, @stderr = bidi2pdf("render", "--json", "--url", "https://example.com", "--output", "-") }

      then_ "I get a non-zero exit before any browser is touched" do
        expect(@status).to eq(2)
      end

      and_ "stdout stays empty, since it's still reserved for the raw PDF bytes --output - promised" do
        expect(@stdout).to eq("")
      end

      and_ "I get INVALID_CONFIG on stderr, explaining the two streams conflict" do
        # stderr's first lines are this sandbox's own RubyGems boot warnings from spawning a
        # fresh interpreter inside an already-bundled process (see the bidi2pdf helper's own
        # comment above) - real noise a real agent's shell wouldn't see, but harmless here since
        # the actual payload is always the last line, exactly like every real Bidi2pdf.logger
        # line that could otherwise land on stderr alongside it.
        expect(JSON.parse(@stderr.lines.last)["error"]["code"]).to eq("INVALID_CONFIG")
      end
    end
  end
end
