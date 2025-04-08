# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module Commands
      module Base
        def method_name = raise(NotImplementedError, "Must be implemented in subclass")

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
      end
    end
  end
end
