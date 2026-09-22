# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::Recipe::Loader do
  def write_tmp(name, content)
    path = tmp_file("recipe-loader-#{SecureRandom.hex(4)}-#{name}")
    File.write(path, content)
    path
  end

  describe ".load" do
    it "loads a YAML recipe into a Hash" do
      path = write_tmp("r.yml", "version: 1\nsource:\n  url: https://example.com\n")

      expect(described_class.load(path)).to eq("version" => 1, "source" => { "url" => "https://example.com" })
    end

    it "loads a JSON recipe into a Hash" do
      path = write_tmp("r.json", { version: 1, source: { url: "https://example.com" } }.to_json)

      expect(described_class.load(path)).to eq("version" => 1, "source" => { "url" => "https://example.com" })
    end

    it "raises InvalidRecipeError when the file does not exist" do
      expect { described_class.load(tmp_file("does-not-exist.yml")) }.to raise_error(Bidi2pdf::InvalidRecipeError, /not found/)
    end

    it "raises InvalidRecipeError for malformed YAML" do
      path = write_tmp("r.yml", "version: [1\n")

      expect { described_class.load(path) }.to raise_error(Bidi2pdf::InvalidRecipeError, /Could not parse/)
    end

    it "raises InvalidRecipeError for malformed JSON" do
      path = write_tmp("r.json", "{not json")

      expect { described_class.load(path) }.to raise_error(Bidi2pdf::InvalidRecipeError, /Could not parse/)
    end

    it "raises InvalidRecipeError when the top level is not a mapping" do
      path = write_tmp("r.yml", "- 1\n- 2\n")

      expect { described_class.load(path) }.to raise_error(Bidi2pdf::InvalidRecipeError, /must be a mapping/)
    end

    it "raises InvalidRecipeError instead of expanding a YAML alias bomb" do
      path = write_tmp("bomb.yml", <<~YAML)
        a: &a ["x","x","x","x","x","x","x","x","x","x"]
        b: &b [*a,*a,*a,*a,*a,*a,*a,*a,*a,*a]
        c: [*b,*b,*b,*b,*b,*b,*b,*b,*b,*b]
      YAML

      expect { described_class.load(path) }.to raise_error(Bidi2pdf::InvalidRecipeError, /Could not parse/)
    end

    it "raises InvalidRecipeError instead of instantiating a disallowed Ruby object" do
      path = write_tmp("r.yml", "a: !ruby/object:Kernel {}\n")

      expect { described_class.load(path) }.to raise_error(Bidi2pdf::InvalidRecipeError, /Could not parse/)
    end

    # rubocop:disable-next RSpec/MultipleExpectations
    it "raises InvalidRecipeError for a file over MAX_BYTES, without reading it into memory first" do
      path = write_tmp("big.yml", "x")
      allow(File).to receive(:size).with(path).and_return(described_class::MAX_BYTES + 1)
      allow(File).to receive(:read).and_call_original

      expect { described_class.load(path) }.to raise_error(Bidi2pdf::InvalidRecipeError, /too large/)
      expect(File).not_to have_received(:read).with(path)
    end

    # rubocop:disable-next RSpec/MultipleExpectations
    it "truncates a parser error message so it cannot echo a large or sensitive content snippet verbatim" do
      path = write_tmp("r.yml", "a: \"#{"x" * 1000}")

      expect { described_class.load(path) }.to raise_error(Bidi2pdf::InvalidRecipeError) do |error|
        expect(error.message.bytesize).to be < 1000
      end
    end
  end
end
