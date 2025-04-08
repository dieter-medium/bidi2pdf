# frozen_string_literal: true

#
# needs to be at the top of the file
require "simplecov"

if ENV["COVERAGE"]
  SimpleCov.start do
    add_filter "/spec/"
    add_filter "/vendor/"
    # Add any other paths you want to exclude

    add_group "Lib", "lib"

    track_files "lib/**/*.rb"
  end
end

require "bidi2pdf"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  config.order = :random

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.define_derived_metadata(file_path: %r{/spec/unit/}) do |metadata|
    metadata[:unit] = true
  end

  config.define_derived_metadata(file_path: %r{/spec/integration/}) do |metadata|
    metadata[:integration] = true
  end

  config.define_derived_metadata(file_path: %r{/spec/acceptance/}) do |metadata|
    metadata[:acceptance] = true
  end
end

require_relative "support/default_dirs_helper" # just to ensure that the folder definitions are loaded first

Dir[File.expand_path("shared/**/*.rb", __dir__)].each { |f| require f }
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }
