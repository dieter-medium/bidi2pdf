# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:suite, :acceptance) do
    puts "[ACCEPTANCE TEST] ..."
  end

  config.after(:suite, :acceptance) do
    puts "[ACCEPTANCE TEST] Cleaning up."
  end
end
