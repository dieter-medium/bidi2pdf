# frozen_string_literal: true

module ChromedriverTestHelper
  def session_url
    RSpec.configuration.chromedriver_container.session_url
  end
end
