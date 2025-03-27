# frozen_string_literal: true

module Bidi2pdf
  module Utils
    def timed(operation_name)
      start_time = Time.now
      result = yield
      elapsed = Time.now - start_time
      Bidi2pdf.logger.debug "#{operation_name} completed in #{elapsed.round(3)}s"
      result
    end

    module_function :timed
  end
end
