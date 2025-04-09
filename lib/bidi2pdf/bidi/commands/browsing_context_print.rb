# frozen_string_literal: true

require_relative "print_parameters_validator"

module Bidi2pdf
  module Bidi
    module Commands
      class BrowsingContextPrint
        include Base

        def initialize(context:, print_options:)
          @context = context
          @print_options = print_options || { background: true }

          PrintParametersValidator.validate!(@print_options)
        end

        def params
          @print_options.merge(context: @context)
        end

        def method_name
          "browsingContext.print"
        end
      end
    end
  end
end
