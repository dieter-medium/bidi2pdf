# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module Commands
      # Base module for defining WebSocket commands in the Bidi2pdf library.
      # This module provides common functionality for creating, comparing, and
      # inspecting WebSocket command payloads.
      module Base
        # Abstract method that must be implemented in subclasses to define the
        # WebSocket command method name.
        #
        # @raise [NotImplementedError] If the method is not implemented in a subclass.
        def method_name = raise(NotImplementedError, "method_name must be implemented in subclass")

        # Returns the parameters for the WebSocket command.
        #
        # @return [Hash] The parameters for the command. Defaults to an empty hash.
        def params = {}

        # Constructs the payload for the WebSocket command.
        #
        # @param [Integer] id The unique identifier for the command.
        # @return [Hash] The payload containing the command ID, method name, and parameters.
        def as_payload(id)
          {
            id: id,
            method: method_name,
            params: params
          }
        end

        # Compares the current command with another command for equality.
        #
        # @param [Object] other The other command to compare.
        # @return [Boolean] True if the commands are equal, false otherwise.
        # rubocop: disable Metrics/AbcSize
        def ==(other)
          return false unless other.respond_to?(:method_name) && other.respond_to?(:params)

          return false unless method_name == other.method_name

          return false unless params.keys.sort == other.params.keys.sort

          params.all? { |key, value| other.params.key?(key) && value == other.params[key] }
        end

        # rubocop: enable Metrics/AbcSize

        # Checks if the current command is hash-equal to another command.
        #
        # @param [Object] other The other command to compare.
        # @return [Boolean] True if the commands are hash-equal, false otherwise.
        def eql?(other)
          return false unless other.is_a?(Bidi2pdf::Bidi::Commands::Base)

          self == other
        end

        # Computes the hash value for the command.
        #
        # @return [Integer] The hash value based on the method name and parameters.
        def hash
          [method_name, params].hash
        end

        # Returns a string representation of the command, with sensitive fields redacted.
        #
        # @return [String] The string representation of the command.
        def inspect
          attributes = redact_sensitive_fields({ method_name: method_name, params: params })

          "#<#{self.class}:#{object_id} #{attributes}>"
        end

        private

        # Redacts sensitive fields in a given object.
        #
        # @param [Object] obj The object to redact.
        # @param [Array<String>] sensitive_keys The list of sensitive keys to redact. Defaults to common sensitive keys.
        # @return [Object] The object with sensitive fields redacted.
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

        # Logs and raises a timeout error for a command.
        #
        # @param [Integer] id The unique identifier for the command.
        # @param [String] method The method name of the command.
        # @param [Hash] params The parameters of the command.
        # @raise [CmdTimeoutError] If the command times out.
        def raise_timeout_error(id, method, params)
          @logger.error "Timeout waiting for response to command #{id}, cmd: #{method}, params: #{redact_sensitive_fields(params).inspect}"

          raise CmdTimeoutError, "Timeout waiting for response to command ID #{id}"
        end
      end
    end
  end
end
