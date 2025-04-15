# frozen_string_literal: true

require_relative "chromedriver_manager"
require_relative "session_runner"
require_relative "bidi/session"

require "securerandom"

module Bidi2pdf
  # This module provides a way to instrument events in the Bidi2pdf library.
  # It it's heavyly inspired by ActiveSupport::Notifications.
  # and thought to be used in a similar way.
  # In Rails environment, ActiveSupport::Notifications should be use instead.
  # via configuration: Bidi2pdf.notification_service = ActiveSupport::Notifications

  # rubocop: disable Lint/RescueException, Lint/SuppressedException
  module Notifications
    Thread.attr_accessor :bidi2pdf_notification_instrumenter

    @subscribers = Hash.new { |h, k| h[k] = [] }

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

    class Event
      attr_reader :name, :transaction_id
      attr_accessor :payload

      def initialize(name, start, ending, transaction_id, payload)
        @name = name
        @payload = payload
        @time = start ? start.to_f * 1_000.0 : start
        @transaction_id = transaction_id
        @end = ending ? ending.to_f * 1_000.0 : ending
      end

      def record # :nodoc:
        start!
        begin
          yield payload if block_given?
        rescue Exception => e
          payload[:exception] = [e.class.name, e.message]
          payload[:exception_object] = e
          raise e
        ensure
          finish!
        end
      end

      def start! = @time = now

      def finish! = @end = now

      def duration = @end - @time

      if @time
        def time
          @time / 1000.0
        end
      end

      if @end
        def end
          @end / 1000.0
        end
      end

      private

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
    end

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

# rubocop: enable Lint/RescueException, Lint/SuppressedException
