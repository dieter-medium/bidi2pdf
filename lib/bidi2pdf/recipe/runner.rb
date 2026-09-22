# frozen_string_literal: true

module Bidi2pdf
  class Recipe
    # Runs a validated recipe's actions and assertions against a navigated tab. A thin dispatch
    # over BrowserTab's own methods, not a parallel action/assertion class hierarchy - a step
    # that needs something BrowserTab cannot do belongs there, not here.
    class Runner
      # Raised on the first failing action/assertion; #entries carries every step run so far
      # (successes and the failure itself), for the caller to report in the recipe result.
      class StepFailure < StandardError
        attr_reader :entries, :cause

        def initialize(entries, cause)
          @entries = entries
          @cause = cause
          super(cause.message)
        end
      end

      attr_reader :state
      attr_accessor :pdf_bytes

      # @param recipe [Bidi2pdf::Recipe]
      # @param tab [Bidi2pdf::Bidi::BrowserTab] a navigated tab (e.g. from Launcher#diagnose)
      # @param collector [Bidi2pdf::ResultCollector] source of #console/#network_failures -
      #   exposed live, so assertions can read them mid-run (see ResultCollector's own docs)
      def initialize(recipe:, tab:, collector:)
        @recipe = recipe
        @tab = tab
        @collector = collector
        @state = {}
        @pdf_bytes = nil
      end

      # @return [Array<Hash>] one entry per action actually run
      # @raise [StepFailure] on the first failing action
      def run_actions
        run_steps(@recipe.actions) { |name, step| dispatch_action(name, @recipe.step_options(step)) }
      end

      # @return [Array<Hash>] one entry per assertion actually run
      # @raise [StepFailure] on the first failing assertion
      def run_assertions
        run_steps(@recipe.assertions) do |name, step|
          ok, details = dispatch_assertion(name, step)
          next { ok: ok, details: details } if ok

          raise Bidi2pdf::PageNotAsExpectedError.new("Assertion '#{name}' failed", details: (details || {}).merge(assertion: name))
        end
      end

      private

      # rubocop:disable-next Metrics/AbcSize
      def run_steps(steps)
        entries = []

        steps.each_with_index do |step, index|
          name = @recipe.step_name(step)
          start = now_ms

          begin
            outcome = yield(name, step)
            entry = { index: index, type: name, ok: true, duration_ms: elapsed_ms(start) }
            entry[:details] = outcome[:details] if outcome.is_a?(Hash) && outcome[:details]
            entries << entry
          rescue Bidi2pdf::Error => e
            entries << { index: index, type: name, ok: false, duration_ms: elapsed_ms(start) }
            raise StepFailure.new(entries, e)
          end
        end

        entries
      end

      def now_ms = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)

      def elapsed_ms(start) = (now_ms - start).round

      # --- actions ---

      # rubocop:disable-next Metrics/AbcSize, Metrics/CyclomaticComplexity
      def dispatch_action(name, opts)
        case name
        when "wait_for" then action_wait_for(opts)
        when "click" then action_click(opts)
        when "evaluate" then action_evaluate(opts)
        when "inject_script" then @tab.inject_script(url: opts["url"], content: opts["content"], id: opts["id"])
        when "inject_style" then @tab.inject_style(url: opts["url"], content: opts["content"], id: opts["id"])
        when "set_viewport" then @tab.set_viewport(width: opts["width"], height: opts["height"], device_pixel_ratio: opts["device_pixel_ratio"])
        when "wait_network_idle" then @tab.wait_until_network_idle(timeout: opts.fetch("timeout", 10))
        end
      end

      def action_wait_for(opts)
        timeout = opts.fetch("timeout", 10)
        condition = wait_for_condition(opts)

        script = <<~JS
          new Promise((resolve, reject) => {
            const deadline = Date.now() + #{(timeout.to_f * 1000).to_i};
            const check = () => {
              let ok;
              try { ok = !!(#{condition}); } catch (e) { ok = false; }
              if (ok) { resolve("done"); return; }
              if (Date.now() >= deadline) { reject(new Error("wait_for timed out")); return; }
              setTimeout(check, 100);
            };
            check();
          });
        JS

        response = @tab.execute_script(script)
        return if response.is_a?(Hash) && response["type"] == "success"

        raise Bidi2pdf::SelectorNotFoundError.new("wait_for timed out after #{timeout}s", details: opts)
      end

      def wait_for_condition(opts)
        return "document.querySelector('.pagedjs_page')" if opts["paged_js"]
        return "document.querySelector(#{opts.fetch("selector").to_json})" if opts["selector"]
        return opts.fetch("script") if opts["script"]

        raise Bidi2pdf::InvalidRecipeError, "wait_for needs one of: selector, paged_js, script"
      end

      def action_click(opts)
        selector = opts.fetch("selector") { raise Bidi2pdf::InvalidRecipeError, "click needs a selector" }

        script = <<~JS
          (function () {
            const el = document.querySelector(#{selector.to_json});
            if (!el) { return false; }
            el.scrollIntoView({ block: "center" });
            el.click();
            return true;
          })()
        JS

        response = @tab.execute_script(script)
        return if response.is_a?(Hash) && response["type"] == "success" && response.dig("result", "value") == true

        raise Bidi2pdf::SelectorNotFoundError.new("click: selector '#{selector}' not found", details: opts)
      end

      def action_evaluate(opts)
        script = opts.fetch("script") { raise Bidi2pdf::InvalidRecipeError, "evaluate needs a script" }

        response = @tab.execute_script(script)
        raise Bidi2pdf::ScriptInjectionError.new("evaluate failed", details: opts) unless response.is_a?(Hash) && response["type"] == "success"

        @state[opts["assign"]] = response.dig("result", "value") if opts["assign"]
      end

      # --- assertions: each returns [ok, details_or_nil] ---

      # rubocop:disable-next Metrics/CyclomaticComplexity
      def dispatch_assertion(name, step)
        case name
        when "selector_exists" then assertion_selector_exists(@recipe.step_options(step))
        when "text_present" then assertion_text_present(@recipe.step_options(step))
        when "no_console_errors" then assertion_no_console_errors
        when "no_network_failures" then assertion_no_network_failures
        when "fonts_loaded" then assertion_fonts_loaded
        when "page_count" then assertion_page_count(@recipe.step_value(step))
        when "pdf_text_present" then assertion_pdf_text_present(@recipe.step_options(step))
        when "pdf_not_blank" then assertion_pdf_not_blank
        end
      end

      def assertion_selector_exists(opts)
        selector = opts.fetch("selector")
        response = @tab.execute_script("!!document.querySelector(#{selector.to_json})")
        [response.is_a?(Hash) && response.dig("result", "value") == true, { selector: selector }]
      end

      def assertion_text_present(opts)
        text = opts.fetch("text")
        response = @tab.execute_script("document.body.innerText")
        body_text = response.is_a?(Hash) ? response.dig("result", "value").to_s : ""
        [body_text.include?(text), { text: text }]
      end

      def assertion_no_console_errors
        errors = @collector.console.select { |entry| entry[:level].to_s == "error" }
        [errors.empty?, errors.empty? ? nil : { console_errors: errors }]
      end

      # Filtering by resource type (a `types:` option) is not implemented: Bidi2pdf::Bidi::
      # NetworkEvent carries an HTTP method, not a resource type, so there is nothing to filter
      # by yet. Every captured failure counts.
      def assertion_no_network_failures
        failures = @collector.network_failures
        [failures.empty?, failures.empty? ? nil : { network_failures: failures }]
      end

      def assertion_fonts_loaded
        response = @tab.execute_script(<<~JS)
          document.fonts.ready.then(function () {
            return document.fonts.ready ? !Array.from(document.fonts).some(function (f) { return f.status === "error"; }) : true;
          })
        JS
        ok = response.is_a?(Hash) && response["type"] == "success" && response.dig("result", "value") != false
        [ok, nil]
      end

      def assertion_page_count(expected)
        actual = Bidi2pdf::PdfInspection.page_count(pdf_bytes)

        ok = expected.is_a?(Hash) ? (expected["min"].nil? || actual.to_i >= expected["min"]) && (expected["max"].nil? || actual.to_i <= expected["max"]) : actual == expected

        [ok, { expected: expected, actual: actual }]
      end

      def assertion_pdf_text_present(opts)
        text = opts.fetch("text")
        extracted = Bidi2pdf::PdfInspection.text(pdf_bytes).to_s
        [extracted.include?(text), { text: text }]
      end

      def assertion_pdf_not_blank
        page_count = Bidi2pdf::PdfInspection.page_count(pdf_bytes).to_i
        text = Bidi2pdf::PdfInspection.text(pdf_bytes).to_s
        [page_count.positive? && !text.strip.empty?, { page_count: page_count, text_present: !text.strip.empty? }]
      end
    end
  end
end
