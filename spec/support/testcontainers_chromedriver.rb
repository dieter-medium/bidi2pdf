# frozen_string_literal: true

require "testcontainers"

class ChromedriverContainer < Testcontainers::DockerContainer
  DEFAULT_CHROMEDRIVER_PORT = 3000
  DEFAULT_IMAGE = "chrome-local:latest"

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

  def build_local_image
    Docker::Image.build_from_dir(build_dir, { "t" => image, "dockerfile" => docker_file }) do |lines|
      lines.split("\n").each do |line|
        if (log = JSON.parse(line)) && log.key?("stream")
          $stdout.write log["stream"]
        end
      end
    end
  end

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
    raise NotFoundError, e.message
  rescue Excon::Error::Socket => e
    raise ConnectionError, e.message
  end

  # rubocop: enable Metrics/AbcSize

  def session_url(protocol: "http")
    "#{protocol}://#{host}:#{mapped_port(port)}/session"
  end
end
