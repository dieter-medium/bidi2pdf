# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module Commands
      class AddIntercept
        include Base

        BEFORE_REQUEST = "beforeRequestSent"
        RESPONSE_STARTED = "responseStarted"
        AUTH_REQUIRED = "authRequired"

        def initialize(context:, phases:, url_patterns:)
          @context = context
          @phases = phases
          @url_patterns = url_patterns

          validate_phases!
        end

        def method_name
          "network.addIntercept"
        end

        def params
          {
            context: @context,
            phases: @phases,
            urlPatterns: @url_patterns
          }.compact
        end

        def validate_phases!
          valid_phases = [BEFORE_REQUEST, RESPONSE_STARTED, AUTH_REQUIRED]

          raise ArgumentError, "Unsupported phase(s): #{@phases}" unless @phases.all? { |phase| valid_phases.include?(phase) }
        end
      end
    end
  end
end
