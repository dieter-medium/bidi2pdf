# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::ExitCodes do
  describe ".for" do
    it "maps every ErrorCodes code this gem raises to a documented exit status" do
      Bidi2pdf::ErrorCodes::MAPPING.each_value do |code|
        expect(described_class::CODE_TO_EXIT).to have_key(code), "#{code} has no exit code mapping"
      end
    end

    it "groups CLI/config/recipe-validation errors under exit 2" do
      %w[MISSING_INPUT MULTIPLE_INPUT_SOURCES EMPTY_INPUT INVALID_CONFIG INVALID_PRINT_OPTION INVALID_RECIPE
         PDF_INSPECTION_UNAVAILABLE].each do |code|
        expect(described_class.for(code)).to eq(2)
      end
    end

    it "groups browser/navigation errors under exit 3" do
      %w[BROWSER_LAUNCH_FAILED BROWSER_DISCONNECTED COMMAND_TIMEOUT NAVIGATION_FAILED NAVIGATION_TIMEOUT
         NAVIGATION_AUTH NAVIGATION_NOT_FOUND DNS_ERROR].each do |code|
        expect(described_class.for(code)).to eq(3)
      end
    end

    it "groups page-not-as-expected errors under exit 4" do
      %w[SELECTOR_NOT_FOUND PAGE_NOT_AS_EXPECTED SCRIPT_ERROR STYLE_ERROR].each do |code|
        expect(described_class.for(code)).to eq(4)
      end
    end

    it "groups output/PDF errors under exit 6" do
      %w[PDF_GENERATION_FAILED SCREENSHOT_FAILED OUTPUT_WRITE_FAILED].each do |code|
        expect(described_class.for(code)).to eq(6)
      end
    end

    it "maps INTERNAL_ERROR to exit 70" do
      expect(described_class.for("INTERNAL_ERROR")).to eq(70)
    end

    it "maps an unknown code to exit 70 too, rather than raising" do
      expect(described_class.for("SOMETHING_NEW")).to eq(70)
    end
  end
end
