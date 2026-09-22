# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::Recipe do
  describe "#step_name/#step_value/#step_options" do
    let(:recipe) { described_class.new({}) }

    it "reads the name of a Hash-shaped step" do
      expect(recipe.step_name({ "click" => { "selector" => "#x" } })).to eq("click")
    end

    it "reads the name of a bare-string step" do
      expect(recipe.step_name("wait_network_idle")).to eq("wait_network_idle")
    end

    it "reads a Hash step's options" do
      expect(recipe.step_options({ "click" => { "selector" => "#x" } })).to eq("selector" => "#x")
    end

    it "reads a scalar step's raw value via #step_value" do
      expect(recipe.step_value({ "page_count" => 2 })).to eq(2)
    end

    it "returns empty options for a scalar step" do
      expect(recipe.step_options({ "no_console_errors" => true })).to eq({})
    end
  end

  describe "#needs_pdf?" do
    it "is true when output.pdf is set" do
      expect(described_class.new({ "output" => { "pdf" => "out.pdf" } }).needs_pdf?).to be true
    end

    it "is true when a PDF assertion is present, even without output.pdf" do
      expect(described_class.new({ "assert" => [{ "page_count" => 1 }] }).needs_pdf?).to be true
    end

    it "is false otherwise" do
      expect(described_class.new({ "output" => { "manifest" => "x.json" } }).needs_pdf?).to be false
    end
  end

  describe "#actions/#assertions default to an empty array" do
    it "actions" do
      expect(described_class.new({}).actions).to eq([])
    end

    it "assertions" do
      expect(described_class.new({}).assertions).to eq([])
    end
  end
end
