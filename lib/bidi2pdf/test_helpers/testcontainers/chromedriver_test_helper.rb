# frozen_string_literal: true

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
        def chrome_args
          chrome_args = Bidi2pdf::Bidi::Session::DEFAULT_CHROME_ARGS.dup

          # within github actions, the sandbox is not supported, when we start our own container
          # some privileges are not available ???
          if ENV["DISABLE_CHROME_SANDBOX"]
            chrome_args << "--no-sandbox"

            puts "🚨 Chrome sandbox disabled"
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
        build_dir: File.join(config.docker_dir, ".."),
        mounts: config.respond_to?(:chromedriver_mounts) ? config.chromedriver_mounts : {}
      )

      puts "🚀 chromedriver container started for tests"
    end
  end

  config.after(:suite) do
    stop_container config.chromedriver_container
  end
end

def stop_container(container)
  if container&.running?

    if ENV["SHOW_CONTAINER_LOGS"]
      puts "Container logs:"
      logs_std, logs_error = container.logs

      puts logs_error
      puts logs_std
    end

    puts "🧹 #{container.image} stopping container..."
    container.stop
  end
  container&.remove
end

def chromedriver_tests_present?
  test_of_kind_present? :chromedriver
end

def test_of_kind_present?(type)
  RSpec.world.filtered_examples.values.flatten.any? { |example| example.metadata[type] }
end

# alias the long class name
ChromedriverTestcontainer = Bidi2pdf::TestHelpers::Testcontainers::ChromedriverContainer

def start_chromedriver_container(build_dir:, mounts:)
  container = ChromedriverTestcontainer.new(ChromedriverTestcontainer::DEFAULT_IMAGE,
                                            build_dir: build_dir,
                                            docker_file: "docker/Dockerfile.chromedriver")

  container.with_filesystem_binds(mounts) if mounts&.any?

  container.start

  container
end
