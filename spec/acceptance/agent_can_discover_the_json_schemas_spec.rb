# frozen_string_literal: true

require "spec_helper"
require "open3"
require "json"

# The real `exe/bidi2pdf` executable, invoked as a genuine subprocess - not
# Bidi2pdf::CLI.start (still in-process) and not RSpec's own #invoke helper (which bypasses
# Thor's real command dispatch entirely - see spec/unit/bidi2pdf/cli_spec.rb's own regression
# test for why that distinction once mattered: a real dispatch bug survived #invoke undetected).
# An LLM agent shells out to this binary and reads back exactly what these scenarios assert on -
# nothing closer to the real, black-box contract is reachable from inside RSpec.
RSpec.feature "As an LLM agent, I want to discover every command's JSON shape without reading README prose", :acceptance do
  # No "bundle", "exec" prefix: this process (rspec itself) is already running under bundle exec,
  # so RUBYOPT/BUNDLE_GEMFILE are already correctly inherited by the child - re-wrapping in a
  # second, nested `bundle exec` corrupts RubyGems' own bin-path resolution in the *wrapper*
  # (confirmed live: the wrapped command's own stdout comes out perfectly correct, but the outer
  # `bundle` process then exits 1 regardless - a known class of double-bundle-exec breakage, not
  # anything about this gem's own code).
  def bidi2pdf(*)
    exe = File.expand_path("../../exe/bidi2pdf", __dir__)
    root = File.expand_path("../..", __dir__)
    out, _err, status = Open3.capture3(exe, *, chdir: root)
    [status.exitstatus, out]
  end

  scenario "Asking for each command's own schema before ever generating output" do
    when_ "I ask for the render schema" do
      before { @status, @stdout = bidi2pdf("schema", "render") }

      then_ "I get exit 0" do
        expect(@status).to eq(0)
      end

      and_ "the JSON on stdout is exactly the schema render --json will later validate against" do
        expect(JSON.parse(@stdout)).to eq(Bidi2pdf::Schema::RENDER)
      end
    end

    when_ "I ask for the diagnose schema" do
      before { @status, @stdout = bidi2pdf("schema", "diagnose") }

      then_ "I get exit 0 and the diagnose shape, not the render one" do
        expect([@status, JSON.parse(@stdout)]).to eq([0, Bidi2pdf::Schema::DIAGNOSE])
      end
    end

    when_ "I ask for the run schema" do
      before { @status, @stdout = bidi2pdf("schema", "run") }

      then_ "I get exit 0 and the run shape, not the render one" do
        expect([@status, JSON.parse(@stdout)]).to eq([0, Bidi2pdf::Schema::RUN])
      end
    end

    when_ "I ask for the recipe schema" do
      before { @status, @stdout = bidi2pdf("schema", "recipe") }

      then_ "I get exit 0 and enough structure to write a recipe without more prompting" do
        parsed = JSON.parse(@stdout)

        expect([@status, parsed]).to eq([0, Bidi2pdf::Schema::RECIPE])
      end

      and_ "the actions/assert arrays name every action and assertion the CLI actually understands" do
        recipe = JSON.parse(@stdout)
        action_names = recipe["properties"]["actions"]["items"]["oneOf"].map { |b| b["required"].first }
        assertion_names = recipe["properties"]["assert"]["items"]["oneOf"].map { |b| b["required"].first }

        expect([action_names, assertion_names]).to eq([Bidi2pdf::Recipe::KNOWN_ACTIONS, Bidi2pdf::Recipe::KNOWN_ASSERTIONS])
      end
    end

    when_ "I ask for an unknown schema kind" do
      before { @status, @stdout = bidi2pdf("schema", "bogus") }

      then_ "I get a non-zero exit and an error I can read, not a Ruby backtrace" do
        expect([@status, @stdout]).to eq([1, ""])
      end
    end
  end
end
