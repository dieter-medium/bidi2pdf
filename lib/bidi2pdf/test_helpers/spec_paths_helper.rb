# frozen_string_literal: true

# This module provides helper methods for managing paths in test environments.
# It includes methods to retrieve directories and generate temporary file paths.
module Bidi2pdf
  module TestHelpers
    # This submodule contains path-related helper methods and configuration for tests.
    module SpecPathsHelper
      # Retrieves the directory path for Docker files.
      # @return [String] the Docker directory path
      def fixture_dir
        TestHelpers.configuration.fixture_dir
      end

      # Retrieves the directory path for fixtures.
      # @return [String] the fixture directory path
      def fixture_file(*)
        File.join(fixture_dir, *)
      end

      # Retrieves the directory path for specs.
      # @return [String] the spec directory path
      def spec_dir
        TestHelpers.configuration.spec_dir
      end

      # Retrieves the directory path for temporary files.
      # @return [String] the temporary directory path
      def tmp_dir
        TestHelpers.configuration.tmp_dir
      end

      # Generates a path for a temporary file by joining the temporary directory with the given parts.
      # @param [Array<String>] parts the parts of the file path to join
      # @return [String] the full path to the temporary file
      def tmp_file(*parts)
        File.join(tmp_dir, *parts)
      end

      # Generates a random temporary directory path.
      # @param [Array<String>] dirs additional directory components to include in the path
      # @param [String, nil] prefix an optional prefix for the directory name
      # @return [String] the full path to the random temporary directory
      def random_tmp_dir(*dirs, prefix: nil)
        base_dirs = [tmp_dir] + dirs.compact
        pfx = prefix || TestHelpers.configuration.prefix
        File.join(*base_dirs, "#{pfx}#{SecureRandom.hex(8)}")
      end
    end

    # Configures RSpec to include and extend SpecPathsHelper for examples with the `:pdf` metadata.
    RSpec.configure do |config|
      # Includes SpecPathsHelper methods in examples with `:pdf` metadata.
      config.include SpecPathsHelper, pdf: true

      # Extends SpecPathsHelper methods to example groups with `:pdf` metadata.
      config.extend SpecPathsHelper, pdf: true
    end
  end
end
