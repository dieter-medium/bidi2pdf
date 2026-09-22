# frozen_string_literal: true

# A minimal, purpose-built JSON Schema (2020-12) matcher covering only the keywords
# Bidi2pdf::Schema::RECIPE actually uses: type, const, enum, required, additionalProperties,
# properties, oneOf, anyOf, items, minimum, maximum. Not a general JSON Schema implementation, and
# deliberately not one - the project has no json-schema/json_schemer runtime dependency and this
# exists only to prove, in spec/unit/bidi2pdf/recipe/schema_validator_contract_spec.rb, that
# Recipe::Validator accepts/rejects exactly what Schema::RECIPE itself would. Extend the keyword
# list here only if a future schema branch genuinely needs one this doesn't cover yet.
module JsonSchemaSubset
  TYPE_CHECKS = {
    "object" => ->(v) { v.is_a?(Hash) },
    "array" => ->(v) { v.is_a?(Array) },
    "string" => ->(v) { v.is_a?(String) },
    "integer" => ->(v) { v.is_a?(Integer) },
    "number" => ->(v) { v.is_a?(Numeric) },
    "boolean" => ->(v) { [true, false].include?(v) },
    "null" => lambda(&:nil?)
  }.freeze

  module_function

  CHECKS = %i[const_ok? enum_ok? type_ok? one_of_ok? any_of_ok? required_ok? additional_properties_ok? properties_ok? items_ok? bounds_ok?].freeze

  def matches?(schema, value)
    CHECKS.all? { |check| public_send(check, schema, value) }
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

    known = (schema["properties"] || {}).keys
    (value.keys - known).empty?
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
end

RSpec::Matchers.define :satisfy_schema do |schema|
  match { |value| JsonSchemaSubset.matches?(schema, value) }

  description { "satisfy the given JSON Schema" }
end
