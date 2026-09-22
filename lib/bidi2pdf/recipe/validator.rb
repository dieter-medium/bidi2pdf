# frozen_string_literal: true

module Bidi2pdf
  class Recipe
    # Validates a loaded recipe against the schema `bidi2pdf schema recipe` publishes, before any
    # browser is launched - `bidi2pdf run --validate` runs exactly this and nothing else. Every
    # failure is Bidi2pdf::InvalidRecipeError (or Bidi2pdf::PdfInspectionUnavailableError for a
    # PDF assertion without pdf-reader installed), details carrying a `path` an agent can act on
    # directly.
    class Validator
      def initialize(recipe)
        @recipe = recipe
      end

      def validate!
        check_version
        check_top_level_keys
        check_source
        check_steps("actions", @recipe.actions, Recipe::KNOWN_ACTIONS)
        check_steps("assert", @recipe.assertions, Recipe::KNOWN_ASSERTIONS)
        check_wait_for_conditions
        check_presence_assertions
        check_pdf_assertions_need_pdf_inspection
        check_output
        check_print_options
        check_shape
      end

      private

      def check_version
        return if @recipe.data["version"] == 1

        fail!("version must be 1", path: "version")
      end

      def check_top_level_keys
        unknown = @recipe.data.keys.map(&:to_s) - Recipe::KNOWN_TOP_LEVEL_KEYS
        return if unknown.empty?

        fail!("Unknown top-level key '#{unknown.first}'. Known keys: #{Recipe::KNOWN_TOP_LEVEL_KEYS.join(", ")}", path: unknown.first)
      end

      def check_source
        given = %w[url file stdin].select { |key| @recipe.source[key] }

        fail!("source must specify exactly one of url, file, stdin", path: "source") unless given.size == 1
      end

      def check_steps(section, steps, known)
        steps.each_with_index do |step, index|
          name = @recipe.step_name(step)
          next if known.include?(name)

          fail!("Unknown #{section == "actions" ? "action" : "assertion"} '#{name}'. Known: #{known.join(", ")}", path: "#{section}[#{index}].#{name}")
        end
      end

      # Mirrors Schema::RECIPE_ACTIONS' own wait_for oneOf: exactly one of selector/paged_js/script.
      # --validate runs this check itself rather than relying on Runner#wait_for_condition, whose
      # own "needs one of" error only fires mid-run (after a browser is already launched) and does
      # not catch "more than one given" at all - it just silently prefers paged_js, then selector.
      def check_wait_for_conditions
        @recipe.actions.each_with_index do |step, index|
          next unless @recipe.step_name(step) == "wait_for"

          given = %w[selector paged_js script] & @recipe.step_options(step).keys

          next if given.size == 1

          fail!("wait_for needs exactly one of selector, paged_js, script (got: #{given.empty? ? "none" : given.join(", ")})",
                path: "actions[#{index}].wait_for")
        end
      end

      # Mirrors Schema::RECIPE_ASSERT's own const: true for the 4 presence-only assertions -
      # Runner never reads the value beside them, so anything but `true` is misleading rather than
      # merely unusual (see Recipe::PRESENCE_ONLY_ASSERTIONS' own comment).
      def check_presence_assertions
        @recipe.assertions.each_with_index do |step, index|
          name = @recipe.step_name(step)
          next unless Recipe::PRESENCE_ONLY_ASSERTIONS.include?(name)
          next if @recipe.step_value(step) == true

          fail!("#{name} must be true - a false or missing value is misleading; omit the assertion instead", path: "assert[#{index}].#{name}")
        end
      end

      def check_pdf_assertions_need_pdf_inspection
        return if Bidi2pdf::PdfInspection.available?

        @recipe.assertions.each_with_index do |assertion, index|
          name = @recipe.step_name(assertion)
          next unless Recipe::PDF_ASSERTIONS.include?(name)

          raise Bidi2pdf::PdfInspectionUnavailableError.new(
            "assert[#{index}].#{name} requires the pdf-reader gem",
            details: { path: "assert[#{index}].#{name}", reason: "requires the pdf-reader gem" }
          )
        end
      end

      def check_output
        return if Recipe::KNOWN_OUTPUTS.intersect?(@recipe.output.keys.map(&:to_s))

        fail!("output must specify at least one of #{Recipe::KNOWN_OUTPUTS.join(", ")}", path: "output")
      end

      def check_print_options
        return if @recipe.print_options.empty?

        Bidi2pdf::Bidi::Commands::PrintParametersValidator.validate!(symbolize(@recipe.print_options))
      rescue ArgumentError => e
        raise Bidi2pdf::InvalidPrintOptionError.new("Invalid print option: #{e.message}", details: { path: "print" })
      end

      def symbolize(hash)
        hash.to_h { |key, value| [key.to_sym, value] }
      end

      # Runs last, deliberately: everything above gives a friendlier, more specific message for
      # the case it already knows about (an unknown action name, a non-true presence assertion, a
      # real PrintParametersValidator error, ...), so this only ever fires for a shape violation
      # none of them catches - an extra/unrecognized key sitting alongside an otherwise-valid one
      # (SchemaShape's own doc comment has the concrete examples this closes).
      def check_shape
        violation = SchemaShape.first_violation(Bidi2pdf::Schema::RECIPE, @recipe.data)
        return unless violation

        fail!(violation[:reason], path: violation[:path])
      end

      def fail!(reason, path:)
        raise Bidi2pdf::InvalidRecipeError.new(reason, details: { path: path, reason: reason })
      end
    end
  end
end
