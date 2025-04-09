# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    class EventManager
      attr_reader :type

      def initialize(type)
        @listeners = Hash.new { |h, k| h[k] = [] }
        @type = type
      end

      def on(*event_names, &block)
        event_names.each { |event_name| @listeners[event_name.to_sym] << block }

        block
      end

      def off(event_name, block) = @listeners[event_name.to_sym].delete(block)

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
        Bidi2pdf.logger.debug "#{prefix}: #{message.inspect}"
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
