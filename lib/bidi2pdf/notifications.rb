# frozen_string_literal: true

require_relative "chromedriver_manager"
require_relative "session_runner"
require_relative "bidi/session"
require_relative "notifications/event"
require_relative "notifications/instrumenter"

require "securerandom"

module Bidi2pdf
  # This module provides a way to instrument events in the Bidi2pdf library.
  # It it's heavyly inspired by ActiveSupport::Notifications.
  # and thought to be used in a similar way.
  # In Rails environment, ActiveSupport::Notifications should be used instead.
  # via configuration: config.notification_service = ActiveSupport::Notifications

  module Notifications
    Thread.attr_accessor :bidi2pdf_notification_instrumenter

    @subscribers = Hash.new { |h, k| h[k] = [] }

    class << self
      attr_reader :subscribers

      def instrument(name, payload = {})
        payload = payload.dup

        if listening?(name)
          notify(name, payload) { yield payload if block_given? }
        elsif block_given?
          yield payload
        end
      end

      def subscribe(event_pattern, &block)
        pattern = normalize_pattern(event_pattern)

        @subscribers[pattern] << block

        block
      end

      def unsubscribe(event_pattern, block = nil)
        pattern = normalize_pattern(event_pattern)

        if block
          @subscribers[pattern].delete(block)
        else
          @subscribers[pattern].clear
        end
      end

      # rubocop: disable Style/CaseEquality
      def listening?(name)
        @subscribers.any? do |pattern, blocks|
          pattern === name && blocks.any?
        end
      end

      # rubocop: enable Style/CaseEquality

      private

      def bidi2pdf_notification_instrumenter = Thread.current.bidi2pdf_notification_instrumenter ||= Instrumenter.new

      def notify(name, payload, &) = bidi2pdf_notification_instrumenter.notify(name, payload, &)

      def normalize_pattern(pat)
        case pat
        when String, Regexp then pat
        else
          raise ArgumentError, "Pattern must be String or Regexp"
        end
      end
    end
  end
end
