# frozen_string_literal: true

module Bidi2pdf
  # JSON Schema documents behind `bidi2pdf schema <kind>` - how an agent discovers the shape of
  # --json/--manifest/--json-stream/a recipe file without reading prose documentation. These are
  # the source of truth for those shapes; a change to Result/Diagnose's payload/Recipe::Runner's
  # result shape/Manifest/JsonSubscriber/Recipe's own fields should update the matching schema
  # here in the same change. Kind names match the `command` field a response already carries
  # (`"command": "diagnose"` -> `bidi2pdf schema diagnose`), not the Ruby class names behind them.
  module Schema # rubocop:disable Metrics/ModuleLength
    ERROR = {
      "type" => %w[object null],
      "required" => %w[code message retryable],
      "properties" => {
        "code" => { "type" => "string" },
        "message" => { "type" => "string" },
        "retryable" => { "type" => "boolean" },
        "hint" => { "type" => %w[string null] },
        "details" => { "type" => "object" }
      }
    }.freeze

    NAVIGATION = {
      "type" => %w[object null],
      "properties" => {
        "requested_url" => { "type" => %w[string null] },
        "final_url" => { "type" => %w[string null] },
        "status" => { "type" => %w[integer null] }
      }
    }.freeze

    CONSOLE = {
      "type" => "array",
      "items" => { "type" => "object", "properties" => { "level" => { "type" => "string" }, "text" => { "type" => "string" } } }
    }.freeze

    NETWORK_FAILURES = {
      "type" => "array",
      "items" => {
        "type" => "object",
        "properties" => {
          "url" => { "type" => "string" },
          "method" => { "type" => %w[string null] },
          "status" => { "type" => %w[integer null] },
          "state" => { "type" => "string" }
        }
      }
    }.freeze

    WARNINGS = { "type" => "array", "items" => { "type" => "string" } }.freeze

    RENDER = {
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "title" => "Bidi2pdf::Result (render)",
      "description" => "--json output of `bidi2pdf render`, and the final \"result\" event of its --json-stream",
      "type" => "object",
      "required" => %w[schema_version ok command console network_failures warnings],
      "properties" => {
        "schema_version" => { "const" => 1 },
        "ok" => { "type" => "boolean" },
        "command" => { "const" => "render" },
        "output" => { "type" => %w[string null] },
        "bytes" => { "type" => %w[integer null] },
        "sha256" => { "type" => %w[string null] },
        "pages" => { "type" => %w[integer null], "description" => "null when the pdf-reader gem is unavailable" },
        "duration_ms" => { "type" => %w[integer null] },
        "navigation" => NAVIGATION,
        "console" => CONSOLE,
        "network_failures" => NETWORK_FAILURES,
        "warnings" => WARNINGS,
        "error" => ERROR
      }
    }.freeze

    DIAGNOSE = {
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "title" => "bidi2pdf diagnose result",
      "description" => "--json output of `bidi2pdf diagnose`, and the final \"result\" event of its --json-stream. " \
                        "page/fonts/print_media/paged_js are Bidi2pdf::Diagnose's own parsed script results, loosely " \
                        "shaped here rather than over-specified.",
      "type" => "object",
      "required" => %w[schema_version ok command console network_failures warnings],
      "properties" => {
        "schema_version" => { "const" => 1 },
        "ok" => { "type" => "boolean" },
        "command" => { "const" => "diagnose" },
        "page" => { "type" => %w[object null] },
        "console" => CONSOLE,
        "network_failures" => NETWORK_FAILURES,
        "fonts" => { "type" => %w[object null] },
        "print_media" => { "type" => %w[object null] },
        "paged_js" => { "type" => %w[object null] },
        "screenshot" => { "type" => %w[string null], "description" => "path written, when --screenshot was given" },
        "pdf" => {
          "type" => %w[object null],
          "description" => "present when --pdf was given",
          "properties" => {
            "path" => { "type" => "string" },
            "pages" => { "type" => %w[integer null] },
            "not_blank" => { "type" => %w[boolean null] }
          }
        },
        "warnings" => WARNINGS,
        "error" => ERROR
      }
    }.freeze

    RUN_STEP = {
      "type" => "object",
      "required" => %w[index type ok],
      "properties" => {
        "index" => { "type" => "integer" },
        "type" => { "type" => "string" },
        "ok" => { "type" => "boolean" },
        "duration_ms" => { "type" => "integer" },
        "details" => { "type" => "object" }
      }
    }.freeze

    RUN = {
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "title" => "bidi2pdf run result",
      "description" => "--json output of `bidi2pdf run recipe.yml`, and the final \"result\" event of its --json-stream",
      "type" => "object",
      "required" => %w[schema_version ok command recipe actions assertions warnings],
      "properties" => {
        "schema_version" => { "const" => 1 },
        "ok" => { "type" => "boolean" },
        "command" => { "const" => "run" },
        "recipe" => { "type" => "string", "description" => "the recipe file path given on the command line" },
        "actions" => { "type" => "array", "items" => RUN_STEP },
        "assertions" => { "type" => "array", "items" => RUN_STEP },
        "assigned" => { "type" => "object", "description" => "values captured by evaluate ... assign:, keyed by name" },
        "output" => {
          "type" => %w[object null],
          "description" => "null when the run failed",
          "properties" => {
            "pdf" => { "type" => %w[string null] },
            "manifest" => { "type" => %w[string null] },
            "screenshot" => { "type" => %w[string null] },
            "bytes" => { "type" => %w[integer null] },
            "sha256" => { "type" => %w[string null] },
            "pages" => { "type" => %w[integer null] }
          }
        },
        "duration_ms" => { "type" => %w[integer null] },
        "warnings" => WARNINGS,
        "error" => ERROR
      }
    }.freeze

    MANIFEST = {
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "title" => "Bidi2pdf render manifest",
      "description" => "--manifest FILE output",
      "type" => "object",
      "required" => %w[schema_version bidi2pdf_version created_at input output navigation render],
      "properties" => {
        "schema_version" => { "const" => 1 },
        "bidi2pdf_version" => { "type" => "string" },
        "created_at" => { "type" => "string", "format" => "date-time" },
        "input" => {
          "type" => "object",
          "required" => %w[type],
          "properties" => { "type" => { "type" => "string", "enum" => %w[url html_file stdin] }, "url" => { "type" => %w[string null] } }
        },
        "output" => {
          "type" => "object",
          "properties" => {
            "path" => { "type" => %w[string null] },
            "pages" => { "type" => %w[integer null] },
            "bytes" => { "type" => %w[integer null] },
            "sha256" => { "type" => %w[string null] }
          }
        },
        "browser" => { "type" => "object" },
        "navigation" => NAVIGATION,
        "render" => { "type" => "object", "properties" => { "duration_ms" => { "type" => %w[integer null] } } },
        "console" => CONSOLE,
        "network_failures" => NETWORK_FAILURES,
        "warnings" => WARNINGS,
        "headers" => { "type" => "object", "description" => "present only when custom headers were given; secret-bearing values are redacted" }
      }
    }.freeze

    EVENT = {
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "title" => "Bidi2pdf --json-stream event",
      "description" => "one JSON object per stderr line while --json-stream is active. In structured mode (--json/" \
                        "--output -), the last line is always {event: \"result\", result: <the matching command's " \
                        "own schema - see \"result\"'s own oneOf>}. In human mode (--json-stream given alone), only " \
                        "progress events are emitted - there is no synthetic final \"result\" event, since there is " \
                        "no structured result being built; the human-readable log is the completion/failure signal.",
      "type" => "object",
      "required" => %w[schema_version t_ms event],
      "properties" => {
        "schema_version" => { "const" => 1 },
        "t_ms" => { "type" => "integer", "description" => "milliseconds since the render started" },
        "event" => { "type" => "string", "enum" => %w[navigate page_loaded network_idle console print screenshot result] },
        "url" => { "type" => "string", "description" => "present on a navigate event" },
        "level" => { "type" => "string", "description" => "present on a console event" },
        "text" => { "type" => "string", "description" => "present on a console event" },
        "result" => {
          "description" => "present only on the final \"result\" event (structured mode only); shape depends on which " \
                            "command produced this stream - each branch's own \"command\" value disambiguates",
          "oneOf" => [RENDER, DIAGNOSE, RUN]
        }
      }
    }.freeze

    RECIPE_SOURCE = {
      "description" => "exactly one of url, file, stdin",
      "oneOf" => [
        { "type" => "object", "required" => %w[url], "properties" => { "url" => { "type" => "string" } }, "additionalProperties" => false },
        { "type" => "object", "required" => %w[file], "properties" => { "file" => { "type" => "string" } }, "additionalProperties" => false },
        { "type" => "object", "required" => %w[stdin], "properties" => { "stdin" => { "type" => "boolean" } }, "additionalProperties" => false }
      ]
    }.freeze

    RECIPE_ACTIONS = {
      "description" => "one of the 7 known actions - a thin dispatch over BrowserTab's own methods, see README's " \
                        "Agent and Automation Usage section",
      "oneOf" => [
        {
          "type" => "object", "required" => %w[wait_for], "additionalProperties" => false,
          "properties" => {
            "wait_for" => {
              "type" => "object", "additionalProperties" => false,
              "properties" => { "selector" => { "type" => "string" }, "paged_js" => { "type" => "boolean" }, "script" => { "type" => "string" },
                                "timeout" => { "type" => "number" } },
              "description" => "exactly one of selector, paged_js, script"
            }
          }
        },
        {
          "type" => "object", "required" => %w[click], "additionalProperties" => false,
          "properties" => { "click" => { "type" => "object", "required" => %w[selector], "additionalProperties" => false,
                                         "properties" => { "selector" => { "type" => "string" } } } }
        },
        {
          "type" => "object", "required" => %w[evaluate], "additionalProperties" => false,
          "properties" => { "evaluate" => { "type" => "object", "required" => %w[script], "additionalProperties" => false,
                                            "properties" => { "script" => { "type" => "string" }, "assign" => { "type" => "string" } } } }
        },
        {
          "type" => "object", "required" => %w[inject_script], "additionalProperties" => false,
          "properties" => { "inject_script" => { "type" => "object", "additionalProperties" => false,
                                                 "properties" => { "url" => { "type" => "string" }, "content" => { "type" => "string" },
                                                                   "id" => { "type" => "string" } } } }
        },
        {
          "type" => "object", "required" => %w[inject_style], "additionalProperties" => false,
          "properties" => { "inject_style" => { "type" => "object", "additionalProperties" => false,
                                                "properties" => { "url" => { "type" => "string" }, "content" => { "type" => "string" },
                                                                  "id" => { "type" => "string" } } } }
        },
        {
          "type" => "object", "required" => %w[set_viewport], "additionalProperties" => false,
          "properties" => { "set_viewport" => { "type" => "object", "required" => %w[width height], "additionalProperties" => false,
                                                "properties" => { "width" => { "type" => "number" }, "height" => { "type" => "number" },
                                                                  "device_pixel_ratio" => { "type" => "number" } } } }
        },
        {
          "type" => "object", "required" => %w[wait_network_idle], "additionalProperties" => false,
          "properties" => { "wait_network_idle" => { "type" => "object", "additionalProperties" => false,
                                                     "properties" => { "timeout" => { "type" => "number" } } } }
        }
      ]
    }.freeze

    RECIPE_ASSERT = {
      "description" => "one of the 8 known assertions. The bare-boolean ones (no_console_errors, no_network_failures, " \
                        "fonts_loaded, pdf_not_blank) ignore the boolean's own value - only the key's presence matters, " \
                        "matching Recipe::Runner exactly. The last 3 require the pdf-reader gem at --validate time - " \
                        "a runtime fact this schema cannot express, see the top-level description",
      "oneOf" => [
        {
          "type" => "object", "required" => %w[selector_exists], "additionalProperties" => false,
          "properties" => { "selector_exists" => { "type" => "object", "required" => %w[selector], "additionalProperties" => false,
                                                   "properties" => { "selector" => { "type" => "string" } } } }
        },
        {
          "type" => "object", "required" => %w[text_present], "additionalProperties" => false,
          "properties" => { "text_present" => { "type" => "object", "required" => %w[text], "additionalProperties" => false,
                                                "properties" => { "text" => { "type" => "string" } } } }
        },
        { "type" => "object", "required" => %w[no_console_errors], "additionalProperties" => false,
          "properties" => { "no_console_errors" => { "type" => "boolean" } } },
        { "type" => "object", "required" => %w[no_network_failures], "additionalProperties" => false,
          "properties" => { "no_network_failures" => { "type" => "boolean" } } },
        { "type" => "object", "required" => %w[fonts_loaded], "additionalProperties" => false,
          "properties" => { "fonts_loaded" => { "type" => "boolean" } } },
        {
          "type" => "object", "required" => %w[page_count], "additionalProperties" => false,
          "properties" => {
            "page_count" => {
              "oneOf" => [
                { "type" => "integer" },
                { "type" => "object", "properties" => { "min" => { "type" => "integer" }, "max" => { "type" => "integer" } },
                  "additionalProperties" => false }
              ]
            }
          }
        },
        {
          "type" => "object", "required" => %w[pdf_text_present], "additionalProperties" => false,
          "properties" => { "pdf_text_present" => { "type" => "object", "required" => %w[text], "additionalProperties" => false,
                                                    "properties" => { "text" => { "type" => "string" } } } }
        },
        { "type" => "object", "required" => %w[pdf_not_blank], "additionalProperties" => false,
          "properties" => { "pdf_not_blank" => { "type" => "boolean" } } }
      ]
    }.freeze

    RECIPE_PRINT = {
      "type" => "object",
      "description" => "the same options `bidi2pdf render`'s own print flags map to; validated by " \
                        "Bidi::Commands::PrintParametersValidator",
      "properties" => {
        "background" => { "type" => "boolean" },
        "shrinkToFit" => { "type" => "boolean" },
        "orientation" => { "type" => "string", "enum" => %w[portrait landscape] },
        "scale" => { "type" => "number", "minimum" => 0.1, "maximum" => 2.0 },
        "pageRanges" => { "type" => "array", "items" => { "type" => %w[integer string] } },
        "margin" => {
          "type" => "object",
          "properties" => { "top" => { "type" => "number", "minimum" => 0 }, "bottom" => { "type" => "number", "minimum" => 0 },
                            "left" => { "type" => "number", "minimum" => 0 }, "right" => { "type" => "number", "minimum" => 0 } }
        },
        "page" => {
          "type" => "object",
          "properties" => { "format" => { "type" => "string" }, "width" => { "type" => "number", "minimum" => 0.0352 },
                            "height" => { "type" => "number", "minimum" => 0.0352 } }
        }
      }
    }.freeze

    RECIPE = {
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "title" => "Bidi2pdf recipe",
      "description" => "input to `bidi2pdf run recipe.yml` (YAML or JSON). This schema is meant to be sufficient on " \
                        "its own to generate a recipe `--validate` will accept, with one exception JSON Schema cannot " \
                        "express: a page_count/pdf_text_present/pdf_not_blank assertion also requires the pdf-reader " \
                        "gem to be installed at validation time (a runtime environment fact, not a document-shape " \
                        "one) - `--validate` still catches a violation, with error code PDF_INSPECTION_UNAVAILABLE.",
      "type" => "object",
      "required" => %w[version source],
      "additionalProperties" => false,
      "properties" => {
        "version" => { "const" => 1 },
        "source" => RECIPE_SOURCE,
        "browser" => { "type" => "object", "properties" => { "headless" => { "type" => "boolean" } } },
        "headers" => { "type" => "object" },
        "cookies" => { "type" => "object" },
        "auth" => { "type" => "object", "properties" => { "username" => { "type" => "string" }, "password" => { "type" => "string" } } },
        "actions" => { "type" => "array", "items" => RECIPE_ACTIONS },
        "assert" => { "type" => "array", "items" => RECIPE_ASSERT },
        "print" => RECIPE_PRINT,
        "output" => {
          "type" => "object",
          "description" => "at least one of pdf, manifest, screenshot",
          "anyOf" => [{ "required" => %w[pdf] }, { "required" => %w[manifest] }, { "required" => %w[screenshot] }],
          "properties" => { "pdf" => { "type" => "string" }, "manifest" => { "type" => "string" }, "screenshot" => { "type" => "string" } }
        }
      }
    }.freeze

    ALL = { "render" => RENDER, "diagnose" => DIAGNOSE, "run" => RUN, "manifest" => MANIFEST, "recipe" => RECIPE, "event" => EVENT }.freeze

    def self.for(kind)
      ALL.fetch(kind.to_s) { raise ArgumentError, "Unknown schema '#{kind}' - known: #{ALL.keys.join(", ")}" }
    end
  end
end
