# frozen_string_literal: true

#
# needs to be at the top of the file
require "simplecov"

if ENV["COVERAGE"]
  SimpleCov.start do
    command_name "Job #{ENV["GITHUB_JOB"]}" if ENV["GITHUB_JOB"]

    if ENV["CI"]
      formatter SimpleCov::Formatter::SimpleFormatter
    else
      formatter SimpleCov::Formatter::MultiFormatter.new([
                                                           SimpleCov::Formatter::SimpleFormatter,
                                                           SimpleCov::Formatter::HTMLFormatter
                                                         ])
    end

    add_filter "/spec/"
    add_filter "/vendor/"
    add_filter "lib/bidi2pdf/version.rb"
    # Add any other paths you want to exclude

    add_group "Lib", "lib"

    track_files "lib/**/*.rb"
  end
end

require "bidi2pdf"
require "bidi2pdf/test_helpers"
require "rspec-benchmark"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  config.order = :random

  # Seed global randomization in this process using the `--seed` CLI option.
  # Setting this allows you to use `--seed` to deterministically reproduce
  # test failures related to randomization by passing the same `--seed` value
  # as the one that triggered the failure.
  Kernel.srand config.seed

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

  config.include RSpec::Benchmark::Matchers, benchmark: true
end

Dir[File.expand_path("shared/**/*.rb", __dir__)].each { |f| require f }
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }
