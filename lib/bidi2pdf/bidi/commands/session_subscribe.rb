# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module Commands
      class SessionSubscribe
        include Base

        attr_reader :events

        def initialize(events:)
          @events = events
        end

        def method_name
          "session.subscribe"
        end

        def params
          { events: events }.compact
        end
      end
    end
  end
end
