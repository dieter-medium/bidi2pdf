# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module Commands
      class CreateTab < CreateWindow
        def type = "tab"
      end
    end
  end
end
