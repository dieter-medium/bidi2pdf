# frozen_string_literal: true

%w[vips dhash-vips].each do |dep|
  require dep
rescue LoadError
  warn "Missing #{dep}. Add it to your Gemfile if you're using Bidi2pdf image test helpers."
end

require_relative "images/tiff_helper"
require_relative "images/extractor"
require_relative "images/image_similarity_checker"
require_relative "matchers/contains_pdf_image"
