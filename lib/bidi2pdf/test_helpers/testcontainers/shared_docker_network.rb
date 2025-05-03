# frozen_string_literal: true

RSpec.configure do |config|
  config.add_setting :shared_network, default: nil

  config.before(:suite) do
    examples = RSpec.world.filtered_examples.values.flatten
    uses_containers = examples.any? do |ex|
      ex.metadata[:nginx] || ex.metadata[:chrome] || ex.metadata[:chromedriver] || ex.metadata[:container]
    end

    if uses_containers
      config.shared_network = Docker::Network.create("bidi2pdf-test-net-#{SecureRandom.hex(4)}")
      puts "🕸️  started shared network #{config.shared_network}"
    end
  end

  config.after(:suite) do
    config.shared_network&.remove
  end
end
