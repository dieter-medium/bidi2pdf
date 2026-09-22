# frozen_string_literal: true

module Bidi2pdf
  class Recipe
    # Structural validation against Schema::RECIPE itself, not a hand-duplicated parallel list of
    # rules. Validator's other #check_* methods each enforce one *semantic* rule (an action name
    # is known, a source key is truthy, a presence assertion is `true`) with a friendly, specific
    # message - none of them enforce the schema's own `additionalProperties: false` at every
    # level, so an extra, unrecognized key sitting alongside an otherwise-valid one used to pass
    # silently even though `bidi2pdf schema recipe` would reject it (`{url: "...", stdin: false}`,
    # `{wait_for: {...}, extra: 1}` - two action names in one step, `wait_for: {selector: "#x",
    # bogus: "y"}`). #check_shape (see Validator) closes that whole class of gap generically by
    # walking the schema the CLI already publishes, instead of re-describing "what's allowed" a
    # second time in Ruby - the schema is the one place that description can't drift from itself.
    #
    # Deliberately not a general JSON Schema engine and not a gem dependency: only the keywords
    # Schema::RECIPE actually uses (type, const, enum, required, additionalProperties, properties,
    # oneOf, anyOf, items, minimum, maximum). Extend the keyword list only if a future schema
    # branch genuinely needs one this doesn't cover yet.
    module SchemaShape # rubocop:disable Metrics/ModuleLength
      TYPE_CHECKS = {
        "object" => ->(v) { v.is_a?(Hash) },
        "array" => ->(v) { v.is_a?(Array) },
        "string" => ->(v) { v.is_a?(String) },
        "integer" => ->(v) { v.is_a?(Integer) },
        "number" => ->(v) { v.is_a?(Numeric) },
        "boolean" => ->(v) { [true, false].include?(v) },
        "null" => lambda(&:nil?)
      }.freeze

      CHECKS = %i[const_ok? enum_ok? type_ok? one_of_ok? any_of_ok? required_ok? additional_properties_ok? properties_ok? items_ok? bounds_ok?].freeze

      module_function

      # @return [Boolean] whether value satisfies schema
      def matches?(schema, value)
        CHECKS.all? { |check| public_send(check, schema, value) }
      end

      VIOLATION_CHECKS = %i[
        oneof_violation anyof_violation required_violation additional_properties_violation const_violation enum_violation type_violation
        bounds_violation nested_violation
      ].freeze

      # @return [Hash, nil] {path:, reason:} for the first violation a depth-first walk finds, or
      #   nil if value already satisfies schema. Not necessarily *the* most relevant violation
      #   when several exist at once - good enough to point an agent at the right neighborhood,
      #   not a substitute for reading `bidi2pdf schema recipe` for the exact shape.
      def first_violation(schema, value, path = [])
        return nil if matches?(schema, value)

        VIOLATION_CHECKS.each do |check|
          found = public_send(check, schema, value, path)
          return found if found
        end

        { path: display_path(path), reason: "does not match the schema" }
      end

      def const_ok?(schema, value)
        !schema.key?("const") || schema["const"] == value
      end

      def enum_ok?(schema, value)
        !schema.key?("enum") || schema["enum"].include?(value)
      end

      def type_ok?(schema, value)
        types = Array(schema["type"])
        return true if types.empty?

        types.any? { |t| TYPE_CHECKS.fetch(t).call(value) }
      end

      def one_of_ok?(schema, value)
        return true unless schema["oneOf"]

        schema["oneOf"].one? { |branch| matches?(branch, value) }
      end

      def any_of_ok?(schema, value)
        return true unless schema["anyOf"]

        schema["anyOf"].any? { |branch| matches?(branch, value) }
      end

      def required_ok?(schema, value)
        return true unless schema["required"] && value.is_a?(Hash)

        schema["required"].all? { |key| value.key?(key) }
      end

      def additional_properties_ok?(schema, value)
        return true unless schema["additionalProperties"] == false && value.is_a?(Hash)

        (value.keys - (schema["properties"] || {}).keys).empty?
      end

      def properties_ok?(schema, value)
        return true unless schema["properties"] && value.is_a?(Hash)

        schema["properties"].all? { |key, sub_schema| !value.key?(key) || matches?(sub_schema, value[key]) }
      end

      def items_ok?(schema, value)
        return true unless schema["items"] && value.is_a?(Array)

        value.all? { |item| matches?(schema["items"], item) }
      end

      def bounds_ok?(schema, value)
        return true unless value.is_a?(Numeric)

        (!schema["minimum"] || value >= schema["minimum"]) && (!schema["maximum"] || value <= schema["maximum"])
      end

      def display_path(path)
        path.each_with_object(+"") do |seg, str|
          str << (if seg.start_with?("[")
                    seg
                  else
                    (str.empty? ? seg : ".#{seg}")
                  end)
        end
      end

      # When zero branches match but exactly one is "plausible" (its own required key(s) are
      # present, ignoring additionalProperties), recurse into that one branch for a specific
      # reason/path instead of a bare "matched 0 of N" - this is what turns "actions[0] doesn't
      # match any known action" into "actions[0].wait_for: unknown key(s): bogus".
      def oneof_violation(schema, value, path)
        return nil unless schema["oneOf"]

        matching = schema["oneOf"].select { |branch| matches?(branch, value) }
        return nil if matching.size == 1

        (matching.empty? && single_plausible_violation(schema, value, path)) ||
          { path: display_path(path), reason: "must match exactly one of #{schema["oneOf"].size} known shapes (matched #{matching.size})" }
      end

      def single_plausible_violation(schema, value, path)
        plausible = schema["oneOf"].select { |branch| required_ok?(branch, value) }
        return nil unless plausible.size == 1

        first_violation(plausible.first, value, path)
      end

      def anyof_violation(schema, value, path)
        return nil unless schema["anyOf"]
        return nil if schema["anyOf"].any? { |branch| matches?(branch, value) }

        { path: display_path(path), reason: "must match at least one of #{schema["anyOf"].size} known shapes" }
      end

      def required_violation(schema, value, path)
        return nil unless schema["required"] && value.is_a?(Hash)

        missing = schema["required"] - value.keys
        return nil if missing.empty?

        { path: display_path(path), reason: "missing required key(s): #{missing.join(", ")}" }
      end

      def additional_properties_violation(schema, value, path)
        return nil unless schema["additionalProperties"] == false && value.is_a?(Hash)

        extra = value.keys - (schema["properties"] || {}).keys
        return nil if extra.empty?

        { path: display_path(path), reason: "unknown key(s): #{extra.join(", ")}" }
      end

      def const_violation(schema, value, path)
        return nil unless schema.key?("const") && schema["const"] != value

        { path: display_path(path), reason: "must equal #{schema["const"].inspect}" }
      end

      def enum_violation(schema, value, path)
        return nil unless schema["enum"] && !schema["enum"].include?(value)

        { path: display_path(path), reason: "must be one of #{schema["enum"].inspect}" }
      end

      def type_violation(schema, value, path)
        return nil if type_ok?(schema, value)

        { path: display_path(path), reason: "expected type #{Array(schema["type"]).join(" or ")}" }
      end

      def bounds_violation(schema, value, path)
        return nil unless value.is_a?(Numeric)
        return { path: display_path(path), reason: "must be >= #{schema["minimum"]}" } if schema["minimum"] && value < schema["minimum"]
        return { path: display_path(path), reason: "must be <= #{schema["maximum"]}" } if schema["maximum"] && value > schema["maximum"]

        nil
      end

      def nested_violation(schema, value, path)
        properties_violation(schema, value, path) || items_violation(schema, value, path)
      end

      def properties_violation(schema, value, path)
        return nil unless schema["properties"] && value.is_a?(Hash)

        schema["properties"].each do |key, sub_schema|
          next unless value.key?(key)

          found = first_violation(sub_schema, value[key], path + [key])
          return found if found
        end

        nil
      end

      def items_violation(schema, value, path)
        return nil unless schema["items"] && value.is_a?(Array)

        value.each_with_index do |item, index|
          found = first_violation(schema["items"], item, path + ["[#{index}]"])
          return found if found
        end

        nil
      end
    end
  end
end
