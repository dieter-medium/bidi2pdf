# frozen_string_literal: true

require "pdf-reader"
require "base64"
require "securerandom"

RSpec.shared_examples "a PDF downloader" do
  it "creates the downloaded file with correct content" do
    io = StringIO.new(Base64.decode64(launcher.launch))

    PDF::Reader.open(io) do |reader|
      actual_text = reader.pages.map(&:text)
      expected_text = @golden_sample_text

      expect(actual_text).to match_pdf_text(expected_text)
    end
  end

  it "creates the downloaded file with correct page count" do
    io = StringIO.new(Base64.decode64(launcher.launch))

    PDF::Reader.open(io) do |reader|
      expect(reader.page_count).to eql(@golden_sample_pages)
    end
  end

  context "with file creation" do
    let(:output) do
      tmp_dir = tmp_file "pdf-files"
      FileUtils.mkdir_p(tmp_dir)
      File.join(tmp_dir, "test-#{SecureRandom.hex(8)}.pdf")
    end

    it "creates pdf file" do
      launcher.launch

      PDF::Reader.open(output) do |reader|
        expect(reader.page_count).to eql(@golden_sample_pages)
      end
    end
  end
end
