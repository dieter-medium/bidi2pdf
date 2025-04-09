# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module Commands
      class BrowserClose
        include Base

        def method_name
          "browser.close"
        end
      end
    end
  end
end
