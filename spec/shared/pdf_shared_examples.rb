# frozen_string_literal: true

require "pdf-reader"
require "base64"
require "securerandom"
require "bidi2pdf/test_helpers/images"

RSpec.shared_examples "a PDF downloader" do
  it "creates the downloaded file with correct content" do
    expected_pages_as_text = @golden_sample_text

    expect(launcher.launch).to match_pdf_text(expected_pages_as_text)
  end

  it "containes the expected image" do
    expected_image = @golden_sample_image

    expect(launcher.launch).to contains_pdf_image(expected_image).at_page(3).at_position(1)
  end

  it "creates the downloaded file with correct page count" do
    expect(launcher.launch).to have_pdf_page_count(@golden_sample_pages)
  end

  context "with file creation" do
    let(:output) do
      tmp_dir = tmp_file "pdf-files"
      FileUtils.mkdir_p(tmp_dir)
      File.join(tmp_dir, "test-#{SecureRandom.hex(8)}.pdf")
    end

    it "creates pdf file" do
      launcher.launch

      expect(output).to have_pdf_page_count(@golden_sample_pages)
    end
  end
end
