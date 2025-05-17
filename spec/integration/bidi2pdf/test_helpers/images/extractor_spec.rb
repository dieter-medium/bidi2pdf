# frozen_string_literal: true

require "spec_helper"
require "bidi2pdf/test_helpers/images"

RSpec.describe Bidi2pdf::TestHelpers::Images::Extractor do
  subject(:extractor) { described_class.new(pdf_file) }

  context "when images are included" do
    let(:pdf_file) { fixture_file("pdf-with-images/imagemagick-images.pdf") }
    let(:expected_images) do
      %w[pdf-with-images/smile-deflate.tiff pdf-with-images/smile-lzw.tiff pdf-with-images/smile-pack-bits.tiff pdf-with-images/smile.jpg pdf-with-images/smile.png pdf-with-images/smile.tiff].map { |image| fixture_file(image) }
    end

    it "extracts all images" do
      expect(extractor.all_images).to have_attributes(size: 6)
    end

    (1...6).each do |page_number|
      it "converts the image on page #{page_number}, pos 1 correctly" do
        expected_image = expected_images[page_number - 1]
        image = extractor.image_on_page(1, 1)

        checker = Bidi2pdf::TestHelpers::Images::ImageSimilarityChecker.new(expected_image, image)

        expect(checker).to be_very_similar
      end
    end
  end
end
