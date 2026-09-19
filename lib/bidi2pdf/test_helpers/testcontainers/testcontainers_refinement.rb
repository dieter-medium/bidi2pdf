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

      # Address of the Docker host at which this container's *mapped* ports
      # are reachable from the test process.
      #
      # Resolution belongs to testcontainers: it honours TC_HOST, a tcp:/ssh:
      # DOCKER_HOST, a native local daemon, and a sibling container reaching
      # the daemon over the bridge gateway — and it derives #mapped_port from
      # the same decision, so the two must stay on one path. We only add a
      # fallback for the cases 0.2.0 leaves unresolved.
      #
      # This is not the address containers use to reach each other; for that
      # the helpers join a shared network and address containers by alias.
      def accessible_host
        resolved_host || "localhost"
      end

      # testcontainers-core 0.2.0 cannot resolve a host when the test process
      # runs inside a container and the container under test is on a custom
      # network: #container_gateway_ip hardcodes the "bridge" network key
      # (docker_container.rb:1074), so #host returns nil. On the default
      # bridge it can instead reach docker_container.rb:703, which calls an
      # undefined `bridge_ip`. Both are fixed on testcontainers-ruby main;
      # treat either as "unresolved" and fall back.
      def resolved_host
        value = host
        value unless value.nil? || value.empty?
      rescue NoMethodError
        nil
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
