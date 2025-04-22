# frozen_string_literal: true

require_relative "browser_console_logger"

module Bidi2pdf
  module Bidi
    class NavigationFailedEvents
      attr_reader :context_id, :browser_console_logger

      def initialize(context_id)
        @context_id = context_id
      end

      def handle_event(data)
        event = data["params"]
        method = data["method"]

        if event["context"] == context_id
          handle_response(method, event)
        else
          Bidi2pdf.logger.debug2 "Ignoring Log event: #{method}, context_id: #{context_id}, params: #{event}"
        end
      end

      def handle_response(_method, event)
        url = event["url"]
        navigation = event["navigation"]
        timestamp = event["timestamp"]

        Bidi2pdf.notification_service.instrument("navigation_failed_received.bidi2pdf",
                                                 {
                                                   url: url,
                                                   timestamp: timestamp,
                                                   navigation: navigation
                                                 })

        Bidi2pdf.logger.error "Navigation failed for URL: #{url}, Navigation: #{navigation}"
      end
    end
  end
end
