# frozen_string_literal: true

RSpec::Matchers.define :contains_pdf_image do |expected, tolerance: 10|
  chain :at_page do |page_number|
    @page_number = page_number
  end

  match do |actual_pdf|
    extractor = Bidi2pdf::TestHelpers::PDFReaderUtils::Images::Extractor.new(actual_pdf)
    @images = @page_number ? extractor.images_on_page(@page_number) : extractor.all_images

    @expected_fingerprint = DHashVips::IDHash.fingerprint expected

    @distances = []

    @images.any? do |image|
      actual_fingerprint = DHashVips::IDHash.fingerprint image
      distance = DHashVips::IDHash.distance(@expected_fingerprint, actual_fingerprint)

      @distances << distance

      distance <= tolerance
    end
  end

  failure_message do |_actual_pdf|
    "expected to find one image #{@page_number ? "on page #{@page_number}" : ""} to be perceptually similar (distance ≤ #{tolerance}), " \
      "but Hamming distances have been #{@distances}"
  end
end
