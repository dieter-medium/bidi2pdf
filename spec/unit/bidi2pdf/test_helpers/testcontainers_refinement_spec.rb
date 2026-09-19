# frozen_string_literal: true

RSpec.describe Bidi2pdf::TestHelpers::TestcontainersRefinement do
  subject(:container) { container_class.new(gem_host) }

  let(:container_class) do
    refinement = described_class
    Struct.new(:host) { include refinement }
  end

  let(:gem_host) { "gateway.example" }

  describe "#accessible_host" do
    it "returns the host testcontainers resolved" do
      expect(container.accessible_host).to eq("gateway.example")
    end

    context "when testcontainers resolves no host" do
      let(:gem_host) { nil }

      it "falls back to localhost" do
        expect(container.accessible_host).to eq("localhost")
      end
    end

    context "when testcontainers resolves a blank host" do
      let(:gem_host) { "" }

      it "falls back to localhost" do
        expect(container.accessible_host).to eq("localhost")
      end
    end

    context "when testcontainers raises NoMethodError (the 0.2.0 bridge_ip defect)" do
      subject(:container) { container_class.new }

      let(:container_class) do
        refinement = described_class
        Class.new do
          include refinement

          def host
            raise NoMethodError, "undefined method 'bridge_ip'"
          end
        end
      end

      it "falls back to localhost" do
        expect(container.accessible_host).to eq("localhost")
      end
    end
  end
end
