# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:suite, :integration) do
    puts "[INTEGRATION TEST] ..."
  end

  config.after(:suite, :integration) do
    puts "[INTEGRATION TEST] Cleaning up."
  end
end
