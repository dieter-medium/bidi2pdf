# frozen_string_literal: true

require "spec_helper"

# Plain module-level helper, not an RSpec instance method: CASES below builds its recipe Hashes
# via lambdas evaluated while the example group's own body is still being defined (class-body
# eval), before any example instance exists to call an `it`-scoped helper on.
module SchemaValidatorContractFixtures
  def self.base(overrides = {})
    { "version" => 1, "source" => { "url" => "https://example.com" }, "output" => { "manifest" => "x.json" } }.merge(overrides)
  end
end

# The central invariant `bidi2pdf schema recipe` promises an agent: a recipe accepted by the
# schema is also accepted by `bidi2pdf run recipe.yml --validate`, and vice versa - except for a
# runtime-environment fact JSON Schema cannot express (a PDF assertion needing pdf-reader
# installed; already covered by recipe/validator_spec.rb's own PdfInspectionUnavailableError
# case, not repeated here). Table-driven so a future schema/validator edit that breaks the
# invariant on one specific shape fails with the shape's own name, not a generic diff.
# rubocop:disable-next RSpec/DescribeClass -- this is a cross-cutting contract between Schema::RECIPE
# and Recipe::Validator, not a spec of either one alone; no single described_class fits.
RSpec.describe "Schema::RECIPE <-> Recipe::Validator contract" do
  def schema_accepts?(data)
    JsonSchemaSubset.matches?(Bidi2pdf::Schema::RECIPE, data)
  end

  def validator_accepts?(data)
    Bidi2pdf::Recipe.new(data).validate!
    true
  rescue Bidi2pdf::Error
    false
  end

  fixtures = SchemaValidatorContractFixtures

  cases = [
    { name: "minimal valid recipe", data: -> { { "version" => 1, "source" => { "url" => "https://example.com" }, "output" => { "manifest" => "x.json" } } },
      valid: true },
    { name: "missing output", data: -> { { "version" => 1, "source" => { "url" => "https://example.com" } } }, valid: false },
    { name: "stdin: true", data: -> { fixtures.base("source" => { "stdin" => true }) }, valid: true },
    { name: "stdin: false", data: -> { fixtures.base("source" => { "stdin" => false }) }, valid: false },
    { name: "unknown action", data: -> { fixtures.base("actions" => [{ "teleport" => {} }]) }, valid: false },
    { name: "wait_for with selector", data: -> { fixtures.base("actions" => [{ "wait_for" => { "selector" => "#invoice" } }]) }, valid: true },
    { name: "wait_for with paged_js", data: -> { fixtures.base("actions" => [{ "wait_for" => { "paged_js" => true } }]) }, valid: true },
    { name: "wait_for with script", data: -> { fixtures.base("actions" => [{ "wait_for" => { "script" => "window.ready === true" } }]) }, valid: true },
    { name: "wait_for with no condition", data: -> { fixtures.base("actions" => [{ "wait_for" => {} }]) }, valid: false },
    { name: "wait_for with multiple conditions",
      data: -> { fixtures.base("actions" => [{ "wait_for" => { "selector" => "#invoice", "script" => "true" } }]) }, valid: false },
    { name: "no_console_errors: true", data: -> { fixtures.base("assert" => [{ "no_console_errors" => true }]) }, valid: true },
    { name: "no_console_errors: false", data: -> { fixtures.base("assert" => [{ "no_console_errors" => false }]) }, valid: false },
    { name: "no_network_failures: false", data: -> { fixtures.base("assert" => [{ "no_network_failures" => false }]) }, valid: false },
    { name: "fonts_loaded: false", data: -> { fixtures.base("assert" => [{ "fonts_loaded" => false }]) }, valid: false },
    { name: "pdf_not_blank: false", data: -> { fixtures.base("assert" => [{ "pdf_not_blank" => false }]) }, valid: false },
    { name: "invalid print scale", data: -> { fixtures.base("print" => { "scale" => 10 }) }, valid: false }
  ].freeze

  cases.each do |c|
    it "agree on: #{c[:name]}" do
      data = c[:data].call

      expect([schema_accepts?(data), validator_accepts?(data)]).to eq([c[:valid], c[:valid]])
    end
  end
end
