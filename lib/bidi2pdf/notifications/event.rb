# frozen_string_literal: true

module Bidi2pdf
  # rubocop: disable Lint/RescueException
  module Notifications
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

      def time
        @time / 1000.0 if @time
      end

      def end
        @end / 1000.0 if @end
      end

      private

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
    end
  end
end

# rubocop: enable Lint/RescueException
