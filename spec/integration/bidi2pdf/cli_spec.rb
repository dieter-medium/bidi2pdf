# frozen_string_literal: true

require "spec_helper"
require "bidi2pdf/cli"

# rubocop:disable  RSpec/AnyInstance
RSpec.describe Bidi2pdf::CLI do
  let(:cli_runner) { described_class.new }

  describe "#render" do
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
  end
end
# rubocop:enable  RSpec/AnyInstance
