# frozen_string_literal: true

require "net/http"
require "timeout"

module NginxTestHelper
  def nginx_host
    RSpec.configuration.nginx_container.host
  end

  def nginx_port
    RSpec.configuration.nginx_container.first_mapped_port
  end

  def nginx_url(path = "")
    "http://#{nginx_host}:#{nginx_port}/#{path}"
  end
end
