# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module Commands
      require_relative "commands/base"
      require_relative "commands/create_window"
      require_relative "commands/create_tab"
      require_relative "commands/add_intercept"
      require_relative "commands/set_tab_cookie"
      require_relative "commands/set_usercontext_cookie"
      require_relative "commands/session_status"
      require_relative "commands/get_user_contexts"
      require_relative "commands/script_evaluate"
      require_relative "commands/browser_create_user_context"
      require_relative "commands/browser_remove_user_context"
      require_relative "commands/browser_close"
      require_relative "commands/browsing_context_close"
      require_relative "commands/browsing_context_navigate"
      require_relative "commands/browsing_context_print"
      require_relative "commands/session_subscribe"
      require_relative "commands/session_end"
      require_relative "commands/cancel_auth"
      require_relative "commands/network_continue"
      require_relative "commands/provide_credentials"
    end
  end
end
