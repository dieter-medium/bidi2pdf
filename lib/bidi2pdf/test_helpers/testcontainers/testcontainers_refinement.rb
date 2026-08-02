# frozen_string_literal: true

module Bidi2pdf
  module TestHelpers
    module TestcontainersRefinement
      def id
        @_id
      end

      def aliases
        @aliases ||= []
      end

      def aliases=(aliases)
        @aliases = aliases
      end

      def network
        @_network
      end

      def with_network(network)
        @_network = network
        self
      end

      def with_network_aliases(*aliases)
        self.aliases += aliases
        self
      end

      def container_json
        @_container&.json
      end

      def own_container_id
        # cgroup v2 gives just "0::/", so read mountinfo instead
        File.read("/proc/self/mountinfo")[%r{/docker/containers/([0-9a-f]{64})/}, 1]
      rescue Errno::ENOENT
        nil
      end

      def accessible_host
        tmp_host = host
        tmp_host = "localhost" if %i[host dind].include?(docker_topology)
        tmp_host
      end

      def docker_topology
        return :remote if ENV["DOCKER_HOST"].to_s.match?(/\A(tcp|ssh):/)
        return :host unless File.exist?("/.dockerenv")

        id = own_container_id
        return :unknown unless id

        Docker::Container.get(id) # daemon knows me => we're siblings
        :sibling
      rescue Docker::Error::NotFoundError
        :dind # daemon has never heard of me
      end

      def _container_create_options
        opts = super
        network_name = network&.info&.[]("Name")
        opts["HostConfig"]["NetworkMode"] = network_name

        if network && aliases.any?
          opts["NetworkingConfig"] = {
            "EndpointsConfig" => {
              network_name => {
                "Aliases" => aliases
              }
            }
          }
        end

        opts.compact
      end
    end
  end
end

Testcontainers::DockerContainer.prepend(Bidi2pdf::TestHelpers::TestcontainersRefinement)
