# frozen_string_literal: true

RSpec.describe Bidi2pdf::TestHelpers::Testcontainers::ContainerEndpoint do
  subject(:endpoint) { described_class.new(container, 3000) }

  let(:fake_container_class) do
    Struct.new(:accessible_host, :mapped_ports) do
      def mapped_port(port)
        mapped_ports.fetch(port)
      end
    end
  end

  let(:container) { fake_container_class.new("localhost", { 3000 => 32_768 }) }

  it "builds a URL from the container's accessible host and mapped port" do
    expect(endpoint.url(path: "session")).to eq("http://localhost:32768/session")
  end

  it "defaults to the http scheme" do
    expect(endpoint.url).to start_with("http://")
  end

  it "honours a non-default scheme" do
    expect(endpoint.url(scheme: "ws", path: "session")).to eq("ws://localhost:32768/session")
  end

  it "omits a trailing path segment when path is empty" do
    expect(endpoint.url).to eq("http://localhost:32768/")
  end
end
