# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:all, :acceptance) do
    puts "[ACCEPTANCE TEST] ..."
  end

  config.after(:all, :acceptance) do
    puts "[ACCEPTANCE TEST] Cleaning up."
  end
end
