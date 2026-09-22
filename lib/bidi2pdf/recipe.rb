# frozen_string_literal: true

require_relative "recipe/loader"
require_relative "recipe/validator"
require_relative "recipe/runner"

module Bidi2pdf
  # A recipe is a rendering contract: the waits and preparation a page needs before it is printed,
  # and the properties the resulting PDF must have - not a general browser-automation script.
  # `bidi2pdf run recipe.yml` is Loader -> (an invalid recipe stops here, no browser ever
  # launches) -> Validator -> Runner.
  class Recipe
    KNOWN_TOP_LEVEL_KEYS = %w[version source browser headers cookies auth actions assert print output].freeze
    KNOWN_ACTIONS = %w[wait_for click evaluate inject_script inject_style set_viewport wait_network_idle].freeze
    PAGE_ASSERTIONS = %w[selector_exists text_present no_console_errors no_network_failures fonts_loaded].freeze
    PDF_ASSERTIONS = %w[page_count pdf_text_present pdf_not_blank].freeze
    KNOWN_ASSERTIONS = (PAGE_ASSERTIONS + PDF_ASSERTIONS).freeze
    KNOWN_OUTPUTS = %w[pdf manifest screenshot].freeze
    # These four assertions are pure presence checks - Runner never reads the value beside them
    # (see #assertion_no_console_errors and friends), so a bare key is really what's being
    # asserted. `false`/anything but `true` is therefore misleading, not merely unusual: schema
    # recipe encodes this as `const: true` and Validator#check_presence_assertions enforces it too.
    PRESENCE_ONLY_ASSERTIONS = %w[no_console_errors no_network_failures fonts_loaded pdf_not_blank].freeze

    attr_reader :data, :path

    def self.load(path)
      new(Loader.load(path), path: path)
    end

    def initialize(data, path: nil)
      @data = data
      @path = path
    end

    def validate!
      Validator.new(self).validate!
    end

    def actions = Array(@data["actions"])

    def assertions = Array(@data["assert"])

    def source = @data["source"] || {}

    def browser_options = @data["browser"] || {}

    def headers = @data["headers"] || {}

    def cookies = @data["cookies"] || {}

    def auth = @data["auth"]

    def print_options = @data["print"] || {}

    def output = @data["output"] || {}

    def needs_pdf?
      !!output["pdf"] || assertions.any? { |assertion| PDF_ASSERTIONS.include?(step_name(assertion)) }
    end

    def self.step_name(step)
      step.is_a?(Hash) ? step.keys.first.to_s : step.to_s
    end

    def step_name(step) = self.class.step_name(step)

    # The value beside a step's name - a Hash of options (`wait_for: {selector: ..., timeout:
    # ...}`), a bare scalar (`page_count: 2`, `no_console_errors: true`), or nil.
    def step_value(step)
      step.is_a?(Hash) ? step.values.first : nil
    end

    # step_value coerced to a Hash of options - most actions/assertions take this shape; a bare
    # scalar step (page_count: 2, no_console_errors: true) has no options of its own to offer here,
    # so callers that need the scalar itself use #step_value directly.
    def step_options(step)
      value = step_value(step)
      value.is_a?(Hash) ? value : {}
    end
  end
end
