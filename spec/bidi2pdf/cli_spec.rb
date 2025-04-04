# frozen_string_literal: true

require "spec_helper"
require "bidi2pdf/cli"

# rubocop:disable  RSpec/AnyInstance
RSpec.describe Bidi2pdf::CLI do
  let(:cli_runner) { described_class.new }

  describe "#render" do
    context "with required options only" do
      it "accepts --url and starts launcher" do
        allow_any_instance_of(Bidi2pdf::Launcher).to receive(:launch)
        allow_any_instance_of(Bidi2pdf::Launcher).to receive(:stop)

        expect do
          cli_runner.invoke(:render, [], { url: "http://localhost/test" })
        end.not_to raise_error
      end
    end

    context "when required option :url is missing" do
      it "raises a Thor::Error" do
        expect do
          cli_runner.invoke(:render)
        end.to raise_error(Thor::Error, /Missing required option: --url/)
      end
    end

    context "with YAML config file" do
      let(:config_file) do
        Tempfile.create("bidi2pdf.yml").tap do |f|
          f.write({ "url" => "http://localhost/config" }.to_yaml)
          f.rewind
        end
      end

      it "loads options from the config file" do
        allow_any_instance_of(Bidi2pdf::Launcher).to receive(:launch)
        allow_any_instance_of(Bidi2pdf::Launcher).to receive(:stop)

        expect do
          cli_runner.invoke(:render, [], { config: config_file.path })
        end.not_to raise_error
      end
    end

    context "with print options and validation" do
      it "calls the print option validator" do
        allow_any_instance_of(Bidi2pdf::Launcher).to receive(:launch)
        allow_any_instance_of(Bidi2pdf::Launcher).to receive(:stop)

        validator = class_double(Bidi2pdf::Bidi::PrintParametersValidator, validate!: true)
        stub_const("Bidi2pdf::Bidi::PrintParametersValidator", validator)

        allow_any_instance_of(described_class).to receive(:option_provided?) do |_instance, key|
          %i[scale shrink_to_fit orientation].include?(key)
        end

        cli_runner.invoke(
          :render,
          [],
          {
            url: "http://localhost/test",
            orientation: "portrait",
            scale: 1.2,
            shrink_to_fit: false
          }
        )

        expect(validator).to have_received(:validate!).with(hash_including(:orientation, :scale, :shrinkToFit))
      end
    end

    describe "#template" do
      let(:temp_path) { Tempfile.new("bidi2pdf_template").path }

      it "writes a YAML config template" do
        cli_runner.invoke(:template, [], { output: temp_path })

        content = File.read(temp_path)
        parsed = YAML.safe_load(content)

        expect(parsed).to include("url" => "https://example.com",
                                  "print_options" => hash_including("margin" => hash_including("top" => 1.0)))
      end
    end

    describe "#version" do
      it "prints the current version" do
        expect do
          cli_runner.invoke(:version)
        end.to output(/bidi2pdf #{Regexp.escape(Bidi2pdf::VERSION)}/).to_stdout
      end
    end
  end
end
# rubocop:enable  RSpec/AnyInstance
