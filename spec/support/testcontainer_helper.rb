# frozen_string_literal: true

require "testcontainers"
require "testcontainers/nginx"
require "bidi2pdf/test_helpers/testcontainers/chromedriver_container"
require_relative "nginx_test_helper"
require_relative "chromedriver_test_helper"
require_relative "session_test_helper"

RSpec.configure do |config|
  config.add_setting :nginx_container, default: nil
  config.add_setting :chromedriver_container, default: nil

  config.include NginxTestHelper, nginx: true
  config.include ChromedriverTestHelper, chromedriver: true
  config.include SessionTestHelper, session: true

  config.before(:suite) do
    if nginx_tests_present?
      config.nginx_container = start_nginx_container(
        conf_dir: File.join(config.docker_dir, "nginx"),
        fixture_dir: config.fixture_dir
      )
      wait_for_nginx(config.nginx_container)

      puts "🚀 nginx container started for tests"
    end

    if chromedriver_tests_present?
      config.chromedriver_container = start_chromedriver_container(
        build_dir: File.join(config.docker_dir, ".."),
        fixture_dir: config.fixture_dir
      )

      puts "🚀 chromedriver container started for tests"
    end
  end

  config.after(:suite) do
    stop_container config.nginx_container
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

def nginx_tests_present?
  test_of_kind_present? :nginx
end

def chromedriver_tests_present?
  test_of_kind_present? :chromedriver
end

def test_of_kind_present?(type)
  RSpec.world.filtered_examples.values.flatten.any? { |example| example.metadata[type] }
end

# alias the long class name
ChromedriverTestcontainer = Bidi2pdf::TestHelpers::Testcontainers::ChromedriverContainer

def start_chromedriver_container(build_dir:, fixture_dir:)
  container = ChromedriverTestcontainer.new(ChromedriverTestcontainer::DEFAULT_IMAGE,
                                            build_dir: build_dir,
                                            docker_file: "docker/Dockerfile.chromedriver")
                                       .with_filesystem_binds(
                                         {
                                           fixture_dir => "/var/www/html"
                                         }
                                       )

  container.start

  container
end

def start_nginx_container(conf_dir:, fixture_dir:)
  container = Testcontainers::NginxContainer.new(
    "nginx:1.27-bookworm"
  ).with_filesystem_binds(
    {
      File.join(conf_dir, "default.conf") => "/etc/nginx/conf.d/default.conf",
      File.join(conf_dir, "htpasswd") => "/etc/nginx/conf.d/.htpasswd",
      fixture_dir => "/var/www/html"
    }
  )

  container.start
end

def wait_for_nginx(container)
  Timeout.timeout(15) do
    loop do
      begin
        if container.running? && container.mapped_port(80) != 0
          response = Net::HTTP.get_response(URI("http://#{container.host}:#{container.mapped_port(80)}/nginx_status"))
          break if response&.code.to_i == 200
        end
      rescue StandardError
        puts "⏳ waiting for nginx to be ready..."
      end
      sleep 0.5
    end
  end
end
