# frozen_string_literal: true

RSpec::Matchers.define :be_alive_process do |_expected|
  match do |pid|
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  failure_message do |pid|
    "expected process #{pid} to be alive"
  end

  description do
    "be alive process"
  end
end
