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

      def _container_create_options
        opts = super
        network_name = network ? network.info["Name"] : nil
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
