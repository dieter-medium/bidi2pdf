# frozen_string_literal: true

require_relative "shared_docker_network"

module Bidi2pdf
  module TestHelpers
    module Testcontainers
      module ChromedriverTestHelper
        def session_url
          chromedriver_container.session_url
        end

        def chromedriver_container
          RSpec.configuration.chromedriver_container
        end
      end

      module SessionTestHelper
        def reporter
          RSpec.configuration.reporter
        end

        def chrome_args
          chrome_args = Bidi2pdf::Bidi::Session::DEFAULT_CHROME_ARGS.dup

          # within github actions, the sandbox is not supported, when we start our own container
          # some privileges are not available ???
          if ENV["DISABLE_CHROME_SANDBOX"]
            chrome_args << "--no-sandbox"

            reporter.message("🚨 Chrome sandbox disabled")
          end
          chrome_args
        end

        def create_session(session_url)
          Bidi2pdf::Bidi::Session.new(session_url: session_url, headless: true, chrome_args: chrome_args)
        end
      end
    end
  end
end

RSpec.configure do |config|
  config.add_setting :chromedriver_container, default: nil

  config.include Bidi2pdf::TestHelpers::Testcontainers::ChromedriverTestHelper, chromedriver: true
  config.include Bidi2pdf::TestHelpers::Testcontainers::SessionTestHelper, session: true

  config.before(:suite) do
    if chromedriver_tests_present?
      config.chromedriver_container = start_chromedriver_container(
        build_dir: File.join(Bidi2pdf::TestHelpers.configuration.docker_dir, ".."),
        mounts: config.respond_to?(:chromedriver_mounts) ? config.chromedriver_mounts : {},
        shared_network: config.shared_network
      )

      reporter.message("🚀 chromedriver container started for tests")
    end
  end

  config.after(:suite) do
    stop_container config.chromedriver_container
  end
end

def stop_container(container)
  return unless container

  dump_container_logs(container) if container.running?
  stop_running_container(container)
  container.remove
end

def dump_container_logs(container)
  return unless ENV["SHOW_CONTAINER_LOGS"]

  stdout, stderr = container.logs
  reporter.message("Container logs:")
  reporter.message(stderr.to_s) unless stderr.to_s.empty?
  reporter.message(stdout.to_s) unless stdout.to_s.empty?
end

def stop_running_container(container)
  return unless container.running?

  reporter.message("🧹 #{container.image} stopping container...")
  container.stop
end

def reporter
  RSpec.configuration.reporter
end

def chromedriver_tests_present?
  test_of_kind_present? :chromedriver
end

def test_of_kind_present?(type)
  RSpec.world.filtered_examples.values.flatten.any? { |example| example.metadata[type] }
end

# alias the long class name
ChromedriverTestcontainer = Bidi2pdf::TestHelpers::Testcontainers::ChromedriverContainer

def start_chromedriver_container(build_dir:, mounts:, shared_network:)
  container = ChromedriverTestcontainer.new(ChromedriverTestcontainer::DEFAULT_IMAGE,
                                            build_dir: build_dir,
                                            docker_file: "docker/Dockerfile.chromedriver")
                                       .with_network(shared_network)
                                       .with_network_aliases("remote-chrome")

  container.with_filesystem_binds(mounts) if mounts&.any?

  container.start

  container
end
