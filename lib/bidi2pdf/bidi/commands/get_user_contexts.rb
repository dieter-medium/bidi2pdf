# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module Commands
      class GetUserContexts
        include Base

        def method_name
          "browser.getUserContexts"
        end
      end
    end
  end
end
