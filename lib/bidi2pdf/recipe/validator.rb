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
        check_pdf_assertions_need_pdf_inspection
        check_output
        check_print_options
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

      def fail!(reason, path:)
        raise Bidi2pdf::InvalidRecipeError.new(reason, details: { path: path, reason: reason })
      end
    end
  end
end
