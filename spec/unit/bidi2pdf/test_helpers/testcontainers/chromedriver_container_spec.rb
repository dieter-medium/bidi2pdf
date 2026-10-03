# frozen_string_literal: true

RSpec.describe Bidi2pdf::TestHelpers::Testcontainers::ChromedriverContainer do
  # Docker's API pulls every tag of an image named without one - dozens of full images since every
  # build is tagged by its commit, and a test run hangs silently in that pull.
  it "names its default image with a tag" do
    expect(described_class::DEFAULT_IMAGE).to match(%r{\A[^:]+/[^:]+:[^:/]+\z})
  end

  it "builds the image from the checkout when BIDI2PDF_BUILD_CHROMEDRIVER_IMAGE is true" do
    expect(described_class.build_locally?("BIDI2PDF_BUILD_CHROMEDRIVER_IMAGE" => "true")).to be(true)
  end

  it "pulls the published image by default" do
    expect(described_class.build_locally?({})).to be(false)
  end
end
