# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module Commands
      require_relative "commands/base"
      require_relative "commands/create_window"
      require_relative "commands/create_tab"
      require_relative "commands/add_intercept"
      require_relative "commands/set_cookie"
      require_relative "commands/session_status"
      require_relative "commands/get_user_contexts"
    end
  end
end
