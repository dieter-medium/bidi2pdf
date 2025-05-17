# frozen_string_literal: true

module Bidi2pdf
  module TestHelpers
    class Configuration
      # @!attribute [rw] spec_dir
      #   @return [Pathname] the directory where specs are located
      attr_accessor :spec_dir

      # @!attribute [rw] tmp_dir
      #   @return [String] the directory for temporary files
      attr_accessor :tmp_dir

      # @!attribute [rw] prefix
      #   @return [String] the prefix for temporary files
      attr_accessor :prefix

      # @!attribute [rw] docker_dir
      #  @return [String] the directory for Docker files
      attr_accessor :docker_dir

      # @!attribute [rw] fixture_dir
      # @return [String] the directory for fixture files
      attr_accessor :fixture_dir

      def initialize
        project_root = if defined?(Rails) && Rails.respond_to?(:root)
                         Pathname.new(Rails.root)
                       elsif defined?(Bundler) && Bundler.respond_to?(:root)
                         Pathname.new(Bundler.root)
                       else
                         Pathname.new(Dir.pwd)
                       end

        @spec_dir = project_root.join("spec").expand_path
        @docker_dir = project_root.join("docker")
        @fixture_dir = project_root.join("spec", "fixtures")
        @tmp_dir = project_root.join("tmp")
        @prefix = "tmp_"
      end
    end

    class << self
      # Retrieves the current configuration object for TestHelpers.
      # @return [Configuration] the configuration object
      def configuration
        @configuration ||= Configuration.new
      end

      # Allows configuration of TestHelpers by yielding the configuration object.
      # @yieldparam [Configuration] configuration the configuration object to modify
      def configure
        yield(configuration)
      end
    end
  end

  # Configures RSpec to include and extend SpecPathsHelper for examples with the `:pdf` metadata.
  RSpec.configure do |config|
    # Adds a custom RSpec setting for TestHelpers configuration.
    config.add_setting :bidi2pdf_test_helpers_config, default: TestHelpers.configuration
  end
end
