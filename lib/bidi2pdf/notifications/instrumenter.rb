# frozen_string_literal: true

require "securerandom"

module Bidi2pdf
  # This module provides a way to instrument events in the Bidi2pdf library.
  # It it's heavyly inspired by ActiveSupport::Notifications.
  # and thought to be used in a similar way.
  # In Rails environment, ActiveSupport::Notifications should be use instead.
  # via configuration: Bidi2pdf.notification_service = ActiveSupport::Notifications

  # rubocop: disable Lint/RescueException, Lint/SuppressedException
  module Notifications
    class Instrumenter
      attr_reader :id

      def initialize
        @id = SecureRandom.uuid
      end

      def notify(name, payload, &)
        event = create_event(name, payload)
        result = nil
        begin
          result = event.record(&)
        rescue Exception => e
        end

        subscriber_exceptions = notify_subscribers(name, event)

        raise Bidi2pdf::NotificationsError.new(subscriber_exceptions), cause: subscriber_exceptions.first if subscriber_exceptions.any?
        raise e if e

        result
      end

      private

      def create_event(name, payload)
        Event.new(name, nil, nil, @id, payload)
      end

      # rubocop:disable  Style/CaseEquality
      def notify_subscribers(name, event)
        exceptions = []

        Notifications.subscribers.each do |pattern, blocks|
          next unless pattern === name

          blocks.each do |subscriber|
            subscriber.call(event)
          rescue Exception => e
            exceptions << e
          end
        end

        exceptions
      end

      # rubocop:enable Style/CaseEquality
    end
  end
end

# rubocop: enable Lint/RescueException, Lint/SuppressedException
