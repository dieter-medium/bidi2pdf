# frozen_string_literal: true

require "spec_helper"
require "bidi2pdf/test_helpers/images"

RSpec.describe Bidi2pdf::TestHelpers::Images::ImageSimilarityChecker do
  subject(:checker) { described_class.new(expected_image, images_to_check) }

  context "when images are the same" do
    let(:images_to_check) { [fixture_file("pdf-with-images/smile-deflate.tiff")] }
    let(:expected_image) { fixture_file("pdf-with-images/smile-deflate.tiff") }

    it ".similar? returns true" do
      expect(checker).to be_similar(tolerance: 10)
    end

    it ".very_similar? returns true" do
      expect(checker).to be_very_similar
    end

    it ".slightly_similar? returns true" do
      expect(checker).to be_slightly_similar
    end

    it ".different?? returns false" do
      expect(checker).not_to be_different
    end
  end

  context "when images are very similar" do
    let(:images_to_check) { [fixture_file("test-images/red-blue-circle-1.jpg")] }
    let(:expected_image) { fixture_file("test-images/red-blue-circle.jpg") }

    it ".similar? returns true" do
      expect(checker).not_to be_similar(tolerance: 10)
    end

    it ".very_similar? returns true" do
      expect(checker).to be_very_similar
    end

    it ".slightly_similar? returns true" do
      expect(checker).to be_slightly_similar
    end

    it ".different?? returns false" do
      expect(checker).not_to be_different
    end
  end

  context "when images are slightly similar" do
    let(:images_to_check) { [fixture_file("test-images/Eiffel_Tower,_view_from_the_Trocadero,_1_July_2008.jpg")] }
    let(:expected_image) { fixture_file("test-images/Eiffelturm.jpg") }

    it ".similar? returns true" do
      expect(checker).not_to be_similar(tolerance: 10)
    end

    it ".very_similar? returns true" do
      expect(checker).not_to be_very_similar
    end

    it ".slightly_similar? returns true" do
      expect(checker).to be_slightly_similar
    end

    it ".different?? returns false" do
      expect(checker).not_to be_different
    end
  end

  context "when images are different" do
    let(:images_to_check) { [fixture_file("pdf-with-images/smile-deflate.tiff")] }
    let(:expected_image) { fixture_file("test-images/Eiffelturm.jpg") }

    it ".similar? returns true" do
      expect(checker).not_to be_similar(tolerance: 10)
    end

    it ".very_similar? returns true" do
      expect(checker).not_to be_very_similar
    end

    it ".slightly_similar? returns true" do
      expect(checker).not_to be_slightly_similar
    end

    it ".different?? returns false" do
      expect(checker).to be_different
    end
  end
end
