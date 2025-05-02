# frozen_string_literal: true

require "net/http"
require "timeout"

module NginxTestHelper
  def nginx_host
    RSpec.configuration.nginx_container.host
  end

  def nginx_first_alias
    RSpec.configuration.nginx_container.aliases.first
  end

  def nginx_port
    RSpec.configuration.nginx_container.first_mapped_port
  end

  def nginx_first_exposed_port
    RSpec.configuration.nginx_container.send(:container_ports).first
  end

  def nginx_url(path = "", use_alias: false)
    if use_alias
      "http://#{nginx_first_alias}:#{nginx_first_exposed_port}/#{path}"
    else
      "http://#{nginx_host}:#{nginx_port}/#{path}"
    end
  end
end
