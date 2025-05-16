# frozen_string_literal: true

module Bidi2pdf
  module TestHelpers
    module Images
      require "dhash-vips"

      class ImageSimilarityChecker
        def initialize(expected_image, images_to_check)
          @expected_image = expected_image.is_a?(Vips::Image) ? expected_image : Vips::Image.new_from_file(expected_image)
          @images_to_check = images_to_check.map { |image_to_check| image_to_check.is_a?(Vips::Image) ? image_to_check : Vips::Image.new_from_file(image_to_check) }
        end

        def similar?(tolerance: 20)
          distances.any? { |distance| distance < tolerance }
        end

        def very_similar?
          similar? tolerance: 20
        end

        def slightly_similar?
          similar? tolerance: 25
        end

        def different?
          !slightly_similar?
        end

        def expected_fingerprint
          @expected_fingerprint ||= fingerprint @expected_image
        end

        def actual_fingerprints
          @actual_fingerprints ||= @images_to_check.map { |image| fingerprint image }
        end

        def distances
          @distances ||= actual_fingerprints.map do |actual_fingerprint|
            DHashVips::IDHash.distance(expected_fingerprint, actual_fingerprint)
          end
        end

        def fingerprint(image)
          image = image.resize(32.0 / [image.width, image.height].min) if image.width < 32 || image.height < 32

          DHashVips::IDHash.fingerprint image
        end
      end
    end
  end
end
