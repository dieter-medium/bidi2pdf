# frozen_string_literal: true

RSpec::Matchers.define :contains_pdf_image do |expected, tolerance: 10|
  chain :at_page do |page_number|
    @page_number = page_number
  end

  chain :at_position do |i|
    @image_number = i
  end

  match do |actual_pdf|
    extractor = Bidi2pdf::TestHelpers::Images::Extractor.new(actual_pdf)
    @images = if @page_number
                @image_number ? [extractor.image_on_page(@page_number, @image_number)].compact : extractor.images_on_page(@page_number)
              else
                extractor.all_images
              end

    @checkers = @images.map { |image| Bidi2pdf::TestHelpers::Images::ImageSimilarityChecker.new(expected, image) }

    @checkers.any? { |checker| checker.similar?(tolerance:) }
  end

  failure_message do |_actual_pdf|
    "expected to find one image #{@page_number ? "on page #{@page_number}" : ""}#{@image_number ? " at position #{@image_number}" : ""} to be perceptually similar (distance ≤ #{tolerance}), " \
      "but Hamming distances have been #{@checkers.map(&:distance).join(", ")}"
  end
end
