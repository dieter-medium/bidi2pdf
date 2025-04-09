# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module Commands
      class SessionEnd
        include Base

        def method_name
          "session.end"
        end
      end
    end
  end
end
