# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::Schema do
  describe ".for" do
    it "serves a schema per known kind" do
      expect(described_class::ALL.keys).to eq(%w[render diagnose run manifest recipe event])
    end

    it "raises for an unknown kind, naming the known ones" do
      expect { described_class.for("bogus") }.to raise_error(ArgumentError, /known: render, diagnose, run, manifest, recipe, event/)
    end
  end

  # The recipe schema's whole purpose is that an agent can generate a valid recipe from it alone,
  # without reading README prose - these checks prove it actually matches
  # Recipe::Validator/Recipe::Runner, not just that it looks plausible.
  describe "RECIPE" do
    def branch_names(schema)
      schema["oneOf"].map { |branch| branch["required"].first }
    end

    it "has exactly one oneOf branch per Recipe::KNOWN_ACTIONS entry" do
      expect(branch_names(described_class::RECIPE_ACTIONS)).to match_array(Bidi2pdf::Recipe::KNOWN_ACTIONS)
    end

    it "has exactly one oneOf branch per Recipe::KNOWN_ASSERTIONS entry" do
      expect(branch_names(described_class::RECIPE_ASSERT)).to match_array(Bidi2pdf::Recipe::KNOWN_ASSERTIONS)
    end

    def validate(overrides = {})
      recipe = { "version" => 1, "source" => { "url" => "https://example.com" }, "output" => { "manifest" => "x.json" } }.merge(overrides)
      Bidi2pdf::Recipe.new(recipe).validate!
    end

    # One example per action, built to satisfy that action's own oneOf branch (required + only
    # the properties it declares), then checked against the real Validator - proves the schema
    # doesn't just look right, a document built from it is actually accepted.
    example_actions = {
      "wait_for" => { "selector" => "#total", "timeout" => 5 },
      "click" => { "selector" => "#show" },
      "evaluate" => { "script" => "1", "assign" => "x" },
      "inject_script" => { "content" => "1" },
      "inject_style" => { "content" => "body{}" },
      "set_viewport" => { "width" => 100, "height" => 100 },
      "wait_network_idle" => { "timeout" => 5 }
    }

    example_actions.each do |name, opts|
      it "accepts a #{name} action built from its own schema branch" do
        expect { validate("actions" => [{ name => opts }]) }.not_to raise_error
      end
    end

    example_assertions = {
      "selector_exists" => { "selector" => "#total" },
      "text_present" => { "text" => "Invoice" },
      "no_console_errors" => true,
      "no_network_failures" => true,
      "fonts_loaded" => true,
      "page_count" => 2,
      "pdf_text_present" => { "text" => "Invoice" },
      "pdf_not_blank" => true
    }

    example_assertions.each do |name, value|
      it "accepts a #{name} assertion built from its own schema branch" do
        expect { validate("assert" => [{ name => value }]) }.not_to raise_error
      end
    end

    it "accepts page_count's {min:, max:} branch too" do
      expect { validate("assert" => [{ "page_count" => { "min" => 1, "max" => 3 } }]) }.not_to raise_error
    end

    it "accepts source's url branch" do
      expect { validate("source" => { "url" => "https://example.com" }) }.not_to raise_error
    end

    it "accepts source's file branch" do
      expect { validate("source" => { "file" => "x.html" }) }.not_to raise_error
    end

    it "accepts source's stdin branch" do
      expect { validate("source" => { "stdin" => true }) }.not_to raise_error
    end

    it "accepts output's pdf branch" do
      expect { validate("output" => { "pdf" => "x.pdf" }) }.not_to raise_error
    end

    it "accepts output's manifest branch" do
      expect { validate("output" => { "manifest" => "x.json" }) }.not_to raise_error
    end

    it "accepts output's screenshot branch" do
      expect { validate("output" => { "screenshot" => "x.png" }) }.not_to raise_error
    end

    it "accepts a print block at the edge of its documented ranges" do
      print = { "scale" => 0.1, "orientation" => "landscape", "margin" => { "top" => 0 }, "page" => { "width" => 0.0352 } }
      expect { validate("print" => print) }.not_to raise_error
    end
  end

  describe "RENDER" do
    it "matches Bidi2pdf::Result's own to_h keys exactly" do
      result_keys = Bidi2pdf::Result.success(command: "render").to_h.keys.map(&:to_s)

      expect(result_keys).to match_array(described_class::RENDER["properties"].keys)
    end
  end

  describe "EVENT" do
    it "keeps result's oneOf branches disambiguated by a distinct command const" do
      commands = described_class::EVENT["properties"]["result"]["oneOf"].map { |branch| branch["properties"]["command"]["const"] }

      expect(commands).to eq(%w[render diagnose run])
    end
  end
end
