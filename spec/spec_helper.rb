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

  # Given/When/Then aliases for acceptance specs, matching bidi2pdf-rails' own
  # spec/rails_helper.rb - a `RSpec.feature "As a <persona>, I want to <goal>"` block reads as the
  # use case itself, not as "a test of class X", which is what made that repo's acceptance suite
  # the clearer of the two to a fresh reader (confirmed by direct comparison this session).
  config.alias_example_group_to :feature, feature: true
  config.alias_example_group_to :when_, feature: true
  config.alias_example_group_to :given, feature: true
  config.alias_example_group_to :scenario, feature: true
  config.alias_example_to :then_, feature: true
  config.alias_example_to :and_, feature: true

  config.include RSpec::Benchmark::Matchers, benchmark: true

  config.include Bidi2pdf::TestHelpers::SpecPathsHelper
  config.extend Bidi2pdf::TestHelpers::SpecPathsHelper

  config.add_setting :chromedriver_mounts, default: { Bidi2pdf::TestHelpers.configuration.fixture_dir.to_s => "/var/www/html" }
end

Dir[File.expand_path("shared/**/*.rb", __dir__)].each { |f| require f }
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }
