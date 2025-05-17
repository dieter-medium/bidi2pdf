# frozen_string_literal: true

require "spec_helper"
require "bidi2pdf/test_helpers/images"

# rubocop:disable RSpec/MultipleExpectations, RSpec/DescribeClass
RSpec.describe "contains_pdf_image matcher" do
  let(:pdf_with_images) { fixture_file("pdf-with-images/imagemagick-images.pdf") }
  let(:present_image) { fixture_file("pdf-with-images/smile-deflate.tiff") }
  let(:absent_image) { fixture_file("test-images/Eiffelturm.jpg") }

  context "when the expected image is present" do
    it "passes on the correct page" do
      expect(pdf_with_images).to contains_pdf_image(present_image, tolerance: 10).at_page(1)
    end

    it "passes without specifying a page if anywhere" do
      expect(pdf_with_images).to contains_pdf_image(present_image, tolerance: 10)
    end
  end

  context "when the expected image is not present" do
    it "fails with a descriptive message" do
      expect do
        expect(pdf_with_images).to contains_pdf_image(absent_image, tolerance: 5).at_page(1).at_position(1)
      end.to raise_error(RSpec::Expectations::ExpectationNotMetError, /expected to find one image on page 1 at position 1/)
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/DescribeClass
