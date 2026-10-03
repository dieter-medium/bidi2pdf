# frozen_string_literal: true

module Bidi2pdf
  module TestHelpers
    module Testcontainers
      class ChromedriverContainer < ::Testcontainers::DockerContainer
        DEFAULT_CHROMEDRIVER_PORT = 3000
        # Always with a tag: Docker's API pulls every tag of an image named without one, and since
        # every image build is tagged by its commit that is dozens of ~500 MB images - a test run
        # then sits silently in the pull for many minutes.
        DEFAULT_IMAGE = "dieters877565/chromedriver:latest"

        # BIDI2PDF_BUILD_CHROMEDRIVER_IMAGE=true: build the image from the checkout (build_dir,
        # docker_file) and run that, so a change to the image is tested before it is published -
        # bidi2pdf's own CI sets it. Unset, the published image is pulled. Testcontainers' #start
        # always pulls, so a locally built tag cannot go through it; #start_local_image builds instead.
        def self.build_locally?(env = ENV)
          env["BIDI2PDF_BUILD_CHROMEDRIVER_IMAGE"] == "true"
        end

        attr_reader :docker_file, :build_dir

        def initialize(image = DEFAULT_IMAGE, **options)
          @docker_file = options.delete(:docker_file) || "Dockerfile"
          @build_dir = options.delete(:build_dir) || options[:working_dir]

          super

          @wait_for ||= add_wait_for(:logs, /ChromeDriver was started successfully on port/)
        end

        def start
          with_exposed_ports(port)
          super
        end

        def port
          DEFAULT_CHROMEDRIVER_PORT
        end

        # rubocop: disable Metrics/AbcSize
        def build_local_image
          old_timeout = Docker.options[:read_timeout]
          Docker.options[:read_timeout] = 60 * 10

          Docker::Image.build_from_dir(build_dir, { "t" => image, "dockerfile" => docker_file }) do |lines|
            lines.split("\n").each do |line|
              next unless (log = JSON.parse(line)) && log.key?("stream")
              next unless log["stream"] && !(trimmed_stream = log["stream"].strip).empty?

              timestamp = Time.now.strftime("[%Y-%m-%dT%H:%M:%S.%6N]")
              $stdout.write "#{timestamp} #{trimmed_stream}\n"
            end
          end

          Docker.options[:read_timeout] = old_timeout
        end

        # rubocop: enable  Metrics/AbcSize

        # rubocop: disable Metrics/AbcSize
        def start_local_image
          build_local_image

          with_exposed_ports(port)

          @_container ||= Docker::Container.create(_container_create_options)
          @_container.start

          @_id = @_container.id
          json = @_container.json
          @name = json["Name"]
          @_created_at = json["Created"]

          @wait_for&.call(self)

          self
        rescue Docker::Error::NotFoundError => e
          raise Testcontainers::NotFoundError, e.message
        rescue Excon::Error::Socket => e
          raise Testcontainers::ConnectionError, e.message
        end

        # rubocop: enable Metrics/AbcSize

        def session_url(protocol: "http")
          ContainerEndpoint.new(self, port).url(scheme: protocol, path: "session")
        end
      end
    end
  end
end
