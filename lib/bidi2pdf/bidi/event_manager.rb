# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    class EventManager
      Listener = Struct.new(:block, :id, :source_location) do
        def initialize(block, id = SecureRandom.uuid)
          super
          self.source_location = block.source_location
        end

        def call(*args)
          block.call(*args)
        end

        def ==(other)
          other.is_a?(Listener) && id == other.id
        end

        alias_method :eql?, :==

        def hash
          id.hash
        end
      end

      attr_reader :type

      def initialize(type)
        @listeners = Concurrent::Hash.new { |h, k| h[k] = [] }
        @type = type
      end

      def on(*event_names, &block)
        Listener.new(block).tap do |listener|
          event_names.each do |event_name|
            @listeners[event_name.to_sym] << listener
            log_msg("Adding #{event_name} listener", listener)
          end
        end
      end

      def off(event_name, listener)
        raise ArgumentError, "Listener not registered" unless listener.is_a?(Listener)

        log_msg("Removing #{event_name} listener", listener)

        @listeners[event_name.to_sym].delete(listener)
      end

      def dispatch(event_name, *args)
        listeners = @listeners[event_name.to_sym] || []

        if event_name.to_s.include?(".")
          toplevel_event_name = event_name.to_s.split(".").first
          listeners += @listeners[toplevel_event_name.to_sym]
        end

        log_msg("Dispatching #{type} '#{event_name}' to #{listeners.size} listeners", args)

        listeners.each { |listener| listener.call(*args) }
      end

      def clear(event_name = nil)
        if event_name
          @listeners[event_name].clear
        else
          @listeners.clear
        end
      end

      private

      def log_msg(prefix, data)
        message = truncate_large_values(data)
        Bidi2pdf.logger.debug3 "#{prefix}: #{message.inspect}"
      end

      # rubocop: disable all
      def truncate_large_values(org, max_length = 50, max_depth = 5, current_depth = 0)
        return "...(too deep)..." if current_depth >= max_depth

        obj = org.dup

        case obj
        when Hash
          obj.each_with_object({}) do |(k, v), result|
            result[k] = if %w[username password].include?(k.to_s.downcase)
                          "[REDACTED]"
                        else
                          truncate_large_values(v, max_length, max_depth, current_depth + 1)
                        end
          end
        when Array
          if obj.size > 10
            obj.take(10).map do |v|
              truncate_large_values(v, max_length, max_depth, current_depth + 1)
            end + ["...(#{obj.size - 10} more items)"]
          else
            obj.map { |v| truncate_large_values(v, max_length, max_depth, current_depth + 1) }
          end
        when String
          if obj.length > max_length
            "#{obj[0...max_length]}... (truncated, total length: #{obj.length})"
          else
            obj
          end
        else
          obj
        end
      end

      # rubocop: enable all
    end
  end
end
