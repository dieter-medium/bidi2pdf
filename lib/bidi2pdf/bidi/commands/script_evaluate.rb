# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module Commands
      class ScriptEvaluate
        include Base

        def initialize(expression:,
                       context:,
                       await_promise: true)
          @expression = expression
          @context = context
          @await_promise = await_promise
        end

        def params
          {
            expression: @expression,
            target: {
              context: @context
            },
            awaitPromise: @await_promise
          }
        end

        def method_name
          "script.evaluate"
        end
      end
    end
  end
end
