# frozen_string_literal: true

require "net/http"
require "timeout"

module NginxTestHelper
  def nginx_host
    RSpec.configuration.nginx_container.accessible_host
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

  # use_alias and the default branch used to derive nginx's port two different ways (this one via
  # ContainerEndpoint's fixed 80, use_alias via container_ports.first) - could silently diverge if
  # the container ever exposed more than one port. Both now go through the same ContainerEndpoint
  # instance, built once with the one port (80) either branch is meant to describe.
  def nginx_url(path = "", use_alias: false)
    endpoint = Bidi2pdf::TestHelpers::Testcontainers::ContainerEndpoint.new(RSpec.configuration.nginx_container, 80)

    use_alias ? endpoint.alias_url(path: path) : endpoint.url(path: path)
  end
end
