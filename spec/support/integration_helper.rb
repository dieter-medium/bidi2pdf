# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:all, :integration) do
    puts "[INTEGRATION TEST] ..."
  end

  config.after(:all, :integration) do
    puts "[INTEGRATION TEST] Cleaning up."
  end
end
