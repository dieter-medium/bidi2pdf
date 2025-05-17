# frozen_string_literal: true

%w[pdf-reader diff-lcs unicode_utils].each do |dep|
  require dep
rescue LoadError
  warn "Missing #{dep}. Add it to your Gemfile if you're using Bidi2pdf test helpers."
end

require "bidi2pdf/test_helpers/configuration"
require "bidi2pdf/test_helpers/pdf_file_helper"
require "bidi2pdf/test_helpers/spec_paths_helper"
require "bidi2pdf/test_helpers/pdf_text_sanitizer"
require "bidi2pdf/test_helpers/pdf_reader_utils"
require "bidi2pdf/test_helpers/matchers/match_pdf_text"
require "bidi2pdf/test_helpers/matchers/contains_pdf_text"
require "bidi2pdf/test_helpers/matchers/have_pdf_page_count"

# don't require "bidi2pdf/test_helpers/matchers/contains_pdf_image.rb" directly, use
# require "bidi2pdf/test_helpers/images" instead, because it requires
# ruby-vips and dhash-vips, and not every one wants to use them
