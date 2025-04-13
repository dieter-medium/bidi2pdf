# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module JsLoggerHelper
      private

      def format_stack_trace(trace)
        trace["callFrames"].each_with_index.map do |frame, index|
          function = frame["functionName"].to_s.empty? ? "(anonymous)" : frame["functionName"]
          "##{index} #{function} at #{frame["url"]}:#{frame["lineNumber"]}:#{frame["columnNumber"]}"
        end.join("\n")
      end
    end
  end
end
