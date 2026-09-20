# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::ChromedriverManager do
  subject(:manager) { described_class.new(port: 0, headless: true) }

  around do |example|
    old_chromedriver_log_level = Bidi2pdf.chromedriver_log_level
    old_logger_level = Bidi2pdf.logger.level

    example.run

    Bidi2pdf.chromedriver_log_level = old_chromedriver_log_level
    Bidi2pdf.logger.level = old_logger_level
  end

  describe "#chromedriver_log_level" do
    it "derives from Bidi2pdf.logger.level when no explicit override is set" do
      Bidi2pdf.chromedriver_log_level = nil
      Bidi2pdf.logger.level = Logger::DEBUG

      expect(manager.send(:chromedriver_log_level)).to eq("ALL")
    end

    it "maps every Bidi2pdf.logger.level to its chromedriver --log-level equivalent" do
      Bidi2pdf.chromedriver_log_level = nil

      {
        Logger::DEBUG => "ALL",
        Logger::INFO => "INFO",
        Logger::WARN => "WARNING",
        Logger::ERROR => "SEVERE"
      }.each do |logger_level, expected|
        Bidi2pdf.logger.level = logger_level

        expect(manager.send(:chromedriver_log_level)).to eq(expected)
      end
    end

    it "uses the explicit override instead, regardless of Bidi2pdf.logger.level" do
      Bidi2pdf.logger.level = Logger::INFO
      Bidi2pdf.chromedriver_log_level = "WARNING"

      expect(manager.send(:chromedriver_log_level)).to eq("WARNING")
    end
  end

  describe "#build_cmd" do
    it "passes the resolved chromedriver_log_level as --log-level" do
      Bidi2pdf.chromedriver_log_level = "WARNING"

      expect(manager.send(:build_cmd)).to include("--log-level=WARNING")
    end
  end
end
