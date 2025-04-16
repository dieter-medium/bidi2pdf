# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::VerboseLogger do
  let(:log_output) { StringIO.new }
  let(:logger) { Logger.new(log_output) }
  let(:verbose_logger) { described_class.new(logger, verbosity) }

  describe "#initialize" do
    [
      { input: 2, expected: 2, description: "sets the verbosity to the given number" },
      { input: -1, expected: 0, description: "clamps the verbosity to the minimum" },
      { input: 5, expected: 3, description: "clamps the verbosity to the maximum" },
      { input: 2.5, expected: 2, description: "rounds the verbosity to the nearest integer" }
    ].each do |test_case|
      context "when verbosity is #{test_case[:input]}" do
        let(:verbosity) { test_case[:input] }

        it test_case[:description] do
          expect(verbose_logger.verbosity).to eq(test_case[:expected])
        end
      end
    end

    [
      { input: :medium, expected: 2, description: "sets the verbosity to the corresponding number" },
      { input: :unknown, expected: 0, description: "defaults to the minimum verbosity" }
    ].each do |test_case|
      context "when verbosity is #{test_case[:input]}" do
        let(:verbosity) { test_case[:input] }

        it test_case[:description] do
          expect(verbose_logger.verbosity).to eq(test_case[:expected])
        end
      end
    end

    context "when verbosity is not provided" do
      let(:verbose_logger) { described_class.new(logger) }
      let(:verbosity) { :low }

      it "defaults to low verbosity" do
        expect(verbose_logger.verbosity).to eq(1)
      end
    end
  end

  shared_examples "debug_method" do |debug_level|
    let(:message) { "test message" }
    let(:method_name) { "debug#{debug_level}" }
    let(:question_method) { "debug#{debug_level}?" }
    let(:bang_method) { "debug#{debug_level}!" }
    let(:log_prefix) { "[D#{debug_level}]" }

    context "when verbosity is equal to debug level" do
      let(:verbosity) { debug_level }

      it "logs a debug message with correct prefix" do
        verbose_logger.send(method_name, message)
        log_output.rewind
        expect(log_output.read).to include("#{log_prefix} test message")
      end

      it "logs a debug message with correct prefix from the block" do
        verbose_logger.send(method_name) { "block message" }
        log_output.rewind
        expect(log_output.read).to include(/#{log_prefix}.*block message/)
      end
    end

    context "when verbosity is less than debug level" do
      let(:verbosity) { debug_level - 1 }

      it "does not log a debug message" do
        verbose_logger.send(method_name, message)
        log_output.rewind
        expect(log_output.read).to be_empty
      end
    end

    describe "#debug#{debug_level}?" do
      context "when verbosity is greater than or equal to debug level" do
        let(:verbosity) { debug_level }

        it "returns true" do
          expect(verbose_logger.send(question_method)).to be true
        end
      end

      context "when verbosity is less than debug level" do
        let(:verbosity) { debug_level - 1 }

        it "returns false" do
          expect(verbose_logger.send(question_method)).to be false
        end
      end
    end

    describe "#debug#{debug_level}!" do
      let(:verbosity) { 0 }

      it "sets verbosity to high" do
        verbose_logger.send(bang_method)
        expect(verbose_logger.verbosity).to eq(3)
      end
    end
  end

  it_behaves_like "debug_method", 1
  it_behaves_like "debug_method", 2
  it_behaves_like "debug_method", 3

  describe "#verbosity_sym" do
    [
      { input: 0, expected: :none },
      { input: 1, expected: :low },
      { input: 2, expected: :medium },
      { input: 3, expected: :high }
    ].each do |test_case|
      context "when verbosity is #{test_case[:input]}" do
        let(:verbosity) { test_case[:input] }

        it "return #{test_case[:expected]}" do
          expect(verbose_logger.verbosity_sym).to eq(test_case[:expected])
        end
      end
    end
  end
end
