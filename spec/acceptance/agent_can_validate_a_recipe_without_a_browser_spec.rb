# frozen_string_literal: true

require "spec_helper"
require "open3"
require "json"
require "securerandom"

# Same real-subprocess boundary as agent_can_discover_the_json_schemas_spec.rb - see its header
# comment for why this, and not Bidi2pdf::CLI.start or RSpec's #invoke, is the right level to
# assert an agent's own experience at.
RSpec.feature "As an LLM agent, I want to validate a recipe before ever launching a browser", :acceptance do
  # See agent_can_discover_the_json_schemas_spec.rb's own comment on this method: no "bundle",
  # "exec" prefix - this process already runs under bundle exec, and re-wrapping breaks the outer
  # bundle wrapper's own exit status even though the wrapped command's stdout stays correct.
  def bidi2pdf(*)
    exe = File.expand_path("../../exe/bidi2pdf", __dir__)
    root = File.expand_path("../..", __dir__)
    out, _err, status = Open3.capture3(exe, *, chdir: root)
    [status.exitstatus, out]
  end

  def write_recipe(yaml)
    path = tmp_file("agent-contract-#{SecureRandom.hex(4)}.yml")
    File.write(path, yaml)
    path
  end

  after { File.delete(@recipe_path) if @recipe_path && File.exist?(@recipe_path) }

  scenario "Submitting a recipe generated straight from schema recipe's own oneOf branches" do
    when_ "the recipe satisfies source's url branch and output's manifest branch" do
      before do
        @recipe_path = write_recipe(<<~YAML)
          version: 1
          source:
            url: https://example.com
          output:
            manifest: out.json
        YAML

        @status, @stdout = bidi2pdf("run", @recipe_path, "--validate", "--json")
      end

      then_ "I get exit 0 without any browser ever being launched" do
        expect(@status).to eq(0)
      end

      and_ "I get back ok: true and the exact recipe path I gave it" do
        parsed = JSON.parse(@stdout)

        expect([parsed["ok"], parsed["recipe"]]).to eq([true, @recipe_path])
      end
    end

    when_ "the recipe uses an action built from one of the actions oneOf branches" do
      before do
        @recipe_path = write_recipe(<<~YAML)
          version: 1
          source:
            url: https://example.com
          actions:
            - wait_for:
                selector: "#total"
          output:
            manifest: out.json
        YAML

        @status, @stdout = bidi2pdf("run", @recipe_path, "--validate", "--json")
      end

      then_ "it validates cleanly, exit 0" do
        expect([@status, JSON.parse(@stdout)["ok"]]).to eq([0, true])
      end
    end
  end

  scenario "Submitting a recipe that violates a real constraint from schema recipe" do
    when_ "I give two of source's mutually exclusive branches at once (url and file)" do
      before do
        @recipe_path = write_recipe(<<~YAML)
          version: 1
          source:
            url: https://example.com
            file: local.html
          output:
            manifest: out.json
        YAML

        @status, @stdout = bidi2pdf("run", @recipe_path, "--validate", "--json")
      end

      then_ "I get a non-zero exit before any browser launch is attempted" do
        expect(@status).to eq(2)
      end

      and_ "I get INVALID_RECIPE, a code I can branch on, not a stack trace" do
        parsed = JSON.parse(@stdout)

        expect([parsed["ok"], parsed["error"]["code"]]).to eq([false, "INVALID_RECIPE"])
      end
    end

    when_ "I name an action this version of bidi2pdf doesn't know" do
      before do
        @recipe_path = write_recipe(<<~YAML)
          version: 1
          source:
            url: https://example.com
          actions:
            - teleport_to_mars: {}
          output:
            manifest: out.json
        YAML

        @status, @stdout = bidi2pdf("run", @recipe_path, "--validate", "--json")
      end

      then_ "I get INVALID_RECIPE naming exactly which step is wrong, not a generic failure" do
        parsed = JSON.parse(@stdout)

        expect([@status, parsed["error"]["code"], parsed["error"]["details"]["path"]]).to eq([2, "INVALID_RECIPE", "actions[0].teleport_to_mars"])
      end
    end
  end
end
