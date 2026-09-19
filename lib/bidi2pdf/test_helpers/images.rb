# frozen_string_literal: true

%w[vips dhash-vips].each do |dep|
  require dep
rescue LoadError
  warn "Missing #{dep}. Add it to your Gemfile if you're using Bidi2pdf image test helpers."
end

# CVE-2026-66066 (Rails Active Storage, 2026-07-29): libvips ships loaders/savers that were never
# fuzz-tested (SVG, JPEG XL, JPEG 2000, BMP, ICO, PSD, anything delegated to ImageMagick, ...) -
# left reachable, a crafted file can trigger arbitrary file read or RCE. Applied once, here, for
# every consumer of this opt-in module (Extractor, ImageSimilarityChecker, contains_pdf_image),
# rather than left to each call site to remember - PNG/JPEG (what this gem's own screenshot/PDF
# rendering actually produces) load through already-fuzzed loaders and are unaffected.
Vips.block_untrusted(true) if defined?(Vips)

require_relative "images/tiff_helper"
require_relative "images/extractor"
require_relative "images/image_similarity_checker"
require_relative "matchers/contains_pdf_image"
