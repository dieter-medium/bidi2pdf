# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module Commands
      class BrowserRemoveUserContext
        include Base

        attr_reader :user_context_id

        def initialize(user_context_id: nil)
          @user_context_id = user_context_id
        end

        def params
          {
            userContext: @user_context_id
          }.compact
        end

        def method_name
          "browser.removeUserContext"
        end
      end
    end
  end
end
