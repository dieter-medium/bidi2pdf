# frozen_string_literal: true

require "testcontainers"
require_relative "nginx_helper"

RSpec.configure do |config|
  config.add_setting :nginx_container, default: nil

  config.include NginxTestHelper, nginx: true

  config.before(:suite) do
    if nginx_tests_present?
      config.nginx_container = start_nginx_container(
        conf_dir: File.join(config.docker_dir, "nginx"),
        fixture_dir: config.fixture_dir
      )
      wait_for_nginx(config.nginx_container)

      puts "🚀 nginx container started for tests"
    end
  end

  config.after(:suite) do
    container = config.nginx_container
    if container&.running?
      puts "🧹 stopping nginx container..."
      container.stop
    end
    container&.remove
  end
end

def nginx_tests_present?
  RSpec.world.filtered_examples.values.flatten.any? { |example| example.metadata[:nginx] }
end

def start_nginx_container(conf_dir:, fixture_dir:)
  container = Testcontainers::DockerContainer.new(
    "nginx:1.27-bookworm",
    exposed_ports: [80],
    filesystem_binds: {
      File.join(conf_dir, "default.conf") => "/etc/nginx/conf.d/default.conf",
      File.join(conf_dir, "htpasswd") => "/etc/nginx/conf.d/.htpasswd",
      fixture_dir => "/var/www/html"
    }
  )

  container.start
  container
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
