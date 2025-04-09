# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module Commands
      module Base
        def method_name = raise(NotImplementedError, "method_name must be implemented in subclass")

        def params = {}

        def as_payload(id)
          {
            id: id,
            method: method_name,
            params: params
          }
        end

        # rubocop: disable Metrics/AbcSize
        def ==(other)
          return false unless other.respond_to?(:method_name) && other.respond_to?(:params)

          return false unless method_name == other.method_name

          return false unless params.keys.sort == other.params.keys.sort

          params.all? { |key, value| other.params.key?(key) && value == other.params[key] }
        end

        # rubocop: enable Metrics/AbcSize

        # Hash equality comparison
        def eql?(other)
          return false unless other.is_a?(Bidi2pdf::Bidi::Commands::Base)

          self == other
        end

        def hash
          [method_name, params].hash
        end

        def inspect
          attributes = redact_sensitive_fields({ method_name: method_name, params: params })

          "#<#{self.class}:#{object_id} #{attributes}>"
        end

        private

        def redact_sensitive_fields(obj, sensitive_keys = %w[value token password authorization username])
          case obj
          when Hash
            obj.transform_values.with_index do |v, idx|
              k = obj.keys[idx]
              sensitive_keys.include?(k.to_s.downcase) ? "[REDACTED]" : redact_sensitive_fields(v, sensitive_keys)
            end
          when Array
            obj.map { |item| redact_sensitive_fields(item, sensitive_keys) }
          else
            obj
          end
        end

        def raise_timeout_error(id, method, params)
          @logger.error "Timeout waiting for response to command #{id}, cmd: #{method}, params: #{redact_sensitive_fields(params).inspect}"

          raise CmdTimeoutError, "Timeout waiting for response to command ID #{id}"
        end
      end
    end
  end
end
