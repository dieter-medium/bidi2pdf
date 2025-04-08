# frozen_string_literal: true

module ChromedriverTestHelper
  def session_url
    chromedriver_container.session_url
  end

  def chromedriver_container
    RSpec.configuration.chromedriver_container
  end
end
