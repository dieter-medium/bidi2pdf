# frozen_string_literal: true

require "yaml"
require "json"

module Bidi2pdf
  class Recipe
    # Reads a recipe file (YAML, or JSON when the extension is .json) into a plain Hash. Never
    # launches a browser - a malformed file fails right here.
    #
    # Security: YAML is parsed with Psych.safe_load and no extra options. Its defaults already
    # refuse both custom type tags (no arbitrary Ruby object instantiation) and aliases - the
    # latter matters concretely: a small file using nested YAML anchors/aliases ("billion laughs")
    # can expand to millions of elements in memory; confirmed live, a 273-byte such file produced
    # 10 million array elements in under 2ms. Neither aliases nor a Date/Time value are used by any
    # field a recipe defines, so neither is turned back on "just in case" - only what the format
    # actually needs is permitted. MAX_BYTES bounds the file itself before it is even parsed.
    module Loader
      MAX_BYTES = 1_048_576 # 1 MiB - generous for a recipe file, small enough to bound a huge one.

      # rubocop:disable-next Metrics/AbcSize
      def self.load(path)
        raise Bidi2pdf::InvalidRecipeError.new("Recipe file not found: #{path}", details: { path: path }) unless File.exist?(path)

        raise Bidi2pdf::InvalidRecipeError.new("Recipe file '#{path}' is too large (max #{MAX_BYTES} bytes)", details: { path: path }) if File.size(path) > MAX_BYTES

        content = File.read(path)
        parsed = path.end_with?(".json") ? JSON.parse(content) : YAML.safe_load(content)

        raise Bidi2pdf::InvalidRecipeError.new("Recipe must be a mapping at the top level", details: { path: "." }) unless parsed.is_a?(Hash)

        parsed
      rescue Psych::Exception, JSON::ParserError => e
        # Psych::Exception covers SyntaxError, AliasesNotEnabled and DisallowedClass alike, so a
        # recipe attempting to use any of the features safe_load refuses fails the same clean way
        # a syntax error would, not with an unhandled exception. The message is truncated the same
        # way Bidi2pdf.truncate_for_log bounds any other value that can hold arbitrary input -
        # a recipe may carry credentials (basic auth, headers), and a parser error's own message
        # can otherwise quote a slice of the offending content straight back.
        raise Bidi2pdf::InvalidRecipeError.new("Could not parse recipe '#{path}': #{Bidi2pdf.truncate_for_log(e.message)}", details: { path: path })
      end
    end
  end
end
