# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::Recipe::Validator do
  def recipe(data)
    Bidi2pdf::Recipe.new(data)
  end

  def valid_data(overrides = {})
    { "version" => 1, "source" => { "url" => "https://example.com" }, "output" => { "pdf" => "out.pdf" } }.merge(overrides)
  end

  it "accepts a minimal valid recipe" do
    expect { recipe(valid_data).validate! }.not_to raise_error
  end

  it "rejects a version other than 1" do
    expect { recipe(valid_data("version" => 2)).validate! }.to raise_error(Bidi2pdf::InvalidRecipeError, /version must be 1/)
  end

  it "rejects an unknown top-level key" do
    expect { recipe(valid_data("bogus" => true)).validate! }.to raise_error(Bidi2pdf::InvalidRecipeError, /Unknown top-level key 'bogus'/)
  end

  describe "source" do
    it "rejects a recipe with no source" do
      expect { recipe(valid_data("source" => {})).validate! }.to raise_error(Bidi2pdf::InvalidRecipeError, /exactly one/)
    end

    it "rejects a recipe with more than one source" do
      data = valid_data("source" => { "url" => "https://example.com", "file" => "x.html" })

      expect { recipe(data).validate! }.to raise_error(Bidi2pdf::InvalidRecipeError, /exactly one/)
    end

    it "accepts a file source" do
      expect { recipe(valid_data("source" => { "file" => "x.html" })).validate! }.not_to raise_error
    end

    it "accepts a stdin source" do
      expect { recipe(valid_data("source" => { "stdin" => true })).validate! }.not_to raise_error
    end
  end

  describe "actions" do
    it "accepts every known action" do
      data = valid_data("actions" => [
                           { "wait_for" => { "selector" => "#x" } }, { "click" => { "selector" => "#x" } }, { "evaluate" => { "script" => "1" } },
                           { "inject_script" => { "content" => "1" } }, { "inject_style" => { "content" => "x" } },
                           { "set_viewport" => { "width" => 100, "height" => 100 } }, { "wait_network_idle" => { "timeout" => 5 } }
                         ])

      expect { recipe(data).validate! }.not_to raise_error
    end

    # rubocop:disable-next RSpec/MultipleExpectations
    it "rejects an unknown action, naming it and its index" do
      data = valid_data("actions" => [{ "click" => { "selector" => "#x" } }, { "clik" => { "selector" => "#x" } }])

      expect { recipe(data).validate! }.to raise_error(Bidi2pdf::InvalidRecipeError) do |error|
        expect([error.message, error.details[:path]]).to eq(["Unknown action 'clik'. Known: #{Bidi2pdf::Recipe::KNOWN_ACTIONS.join(", ")}", "actions[1].clik"])
      end
    end
  end

  describe "assert" do
    it "accepts every known page assertion" do
      data = valid_data("assert" => [
                           { "selector_exists" => { "selector" => "#x" } }, { "text_present" => { "text" => "x" } }, { "no_console_errors" => true },
                           { "no_network_failures" => true }, { "fonts_loaded" => true }
                         ])

      expect { recipe(data).validate! }.not_to raise_error
    end

    # rubocop:disable-next RSpec/MultipleExpectations
    it "rejects an unknown assertion, naming it and its index" do
      data = valid_data("assert" => [{ "selector_exixts" => { "selector" => "#x" } }])

      expect { recipe(data).validate! }.to raise_error(Bidi2pdf::InvalidRecipeError) do |error|
        expect([error.message, error.details[:path]]).to eq(
          ["Unknown assertion 'selector_exixts'. Known: #{Bidi2pdf::Recipe::KNOWN_ASSERTIONS.join(", ")}", "assert[0].selector_exixts"]
        )
      end
    end

    it "accepts a PDF assertion when pdf-reader is available" do
      expect { recipe(valid_data("assert" => [{ "page_count" => 2 }])).validate! }.not_to raise_error
    end

    it "rejects a PDF assertion with PdfInspectionUnavailableError when pdf-reader is not available" do
      Bidi2pdf::PdfInspection.reset_for_testing!
      allow(Bidi2pdf::PdfInspection).to receive(:require).with("pdf-reader").and_raise(LoadError)

      expect { recipe(valid_data("assert" => [{ "page_count" => 2 }])).validate! }.to raise_error(Bidi2pdf::PdfInspectionUnavailableError, /pdf-reader/)
    ensure
      Bidi2pdf::PdfInspection.reset_for_testing!
    end
  end

  describe "output" do
    it "rejects a recipe with no output" do
      expect { recipe(valid_data("output" => {})).validate! }.to raise_error(Bidi2pdf::InvalidRecipeError, /at least one/)
    end

    it "accepts manifest-only output" do
      expect { recipe(valid_data("output" => { "manifest" => "x.json" })).validate! }.not_to raise_error
    end
  end

  describe "print" do
    it "rejects an invalid print option via the existing PrintParametersValidator" do
      expect { recipe(valid_data("print" => { "scale" => 10 })).validate! }.to raise_error(Bidi2pdf::InvalidPrintOptionError)
    end

    it "accepts a valid print option" do
      expect { recipe(valid_data("print" => { "orientation" => "landscape" })).validate! }.not_to raise_error
    end
  end
end
