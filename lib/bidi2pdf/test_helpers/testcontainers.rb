# frozen_string_literal: true

%w[docker testcontainers].each do |dep|
  require dep
rescue LoadError
  warn "Missing #{dep}. Add it to your Gemfile if you're using Bidi2pdf test helpers."
end

module Bidi2pdf
  module TestHelpers
    module Testcontainers
      require_relative "testcontainers/testcontainers_refinement"
      require_relative "testcontainers/chromedriver_container"
      require_relative "testcontainers/chromedriver_test_helper"
    end
  end
end
