# frozen_string_literal: true

require "json"

module Bidi2pdf
  # Collects the render-focused diagnostics behind `bidi2pdf diagnose`: why does the PDF not look
  # like the page, not what the page's content is. Everything here reuses
  # BrowserTab#execute_script - no DOM dump, no headings/links/forms extraction; console and
  # network data come from the caller's own
  # ResultCollector, the same source `render` uses, not from here.
  #
  # Each script returns (or resolves to) a JSON string, extracted via #dig("result", "value") -
  # BiDi's script.evaluate already awaits a returned Promise (awaitPromise: true, see
  # Commands::ScriptEvaluate), so document.fonts.ready needs no wrap_in_promise: wrapper.
  class Diagnose
    PAGE_SCRIPT = <<~JS
      JSON.stringify({
        title: document.title,
        url: window.location.href,
        lang: document.documentElement.lang || null
      })
    JS

    FONTS_SCRIPT = <<~JS
      document.fonts.ready.then(function () {
        var loaded = [];
        var failed = [];
        document.fonts.forEach(function (face) {
          var label = face.family + " " + face.weight + " " + face.style;
          if (face.status === "error") { failed.push(label); } else { loaded.push(label); }
        });
        return JSON.stringify({ status: failed.length > 0 ? "partial" : "loaded", loaded: loaded, failed: failed });
      })
    JS

    PRINT_MEDIA_SCRIPT = <<~JS
      (function () {
        var printSheets = [];
        var pageRules = [];
        var unreadable = [];

        for (var i = 0; i < document.styleSheets.length; i++) {
          var sheet = document.styleSheets[i];
          try {
            var rules = sheet.cssRules || sheet.rules;
            for (var j = 0; j < rules.length; j++) {
              var rule = rules[j];
              if (rule.media && Array.prototype.includes.call(rule.media, "print")) {
                printSheets.push(sheet.href || "(inline)");
              }
              if (typeof CSSRule !== "undefined" && rule.type === CSSRule.PAGE_RULE) {
                pageRules.push(rule.cssText);
              }
            }
          } catch (e) {
            unreadable.push(sheet.href || "(inline)");
          }
        }

        var fixedOrSticky = [];
        var breakInsideAvoidCount = 0;
        var elements = document.querySelectorAll("body *");
        for (var k = 0; k < elements.length; k++) {
          var el = elements[k];
          var computed = window.getComputedStyle(el);
          if (computed.position === "fixed" || computed.position === "sticky") {
            var classPart = typeof el.className === "string" && el.className.trim() ? "." + el.className.trim().split(/\\s+/).join(".") : "";
            var selector = el.id ? "#" + el.id : el.tagName.toLowerCase() + classPart;
            fixedOrSticky.push({ selector: selector, position: computed.position });
          }
          if (computed.breakInside === "avoid" || computed.pageBreakInside === "avoid") {
            breakInsideAvoidCount++;
          }
        }

        return JSON.stringify({
          stylesheets_with_print_rules: Array.from(new Set(printSheets)),
          page_rules: pageRules,
          break_inside_avoid_count: breakInsideAvoidCount,
          fixed_or_sticky_elements: fixedOrSticky,
          unreadable_stylesheets: Array.from(new Set(unreadable))
        });
      })()
    JS

    PAGED_JS_SCRIPT = <<~JS
      (function () {
        var detected = !!(window.Paged || window.PagedPolyfill);
        var pages = document.querySelectorAll(".pagedjs_page").length;
        return JSON.stringify({ detected: detected, ready: pages > 0, pages: pages });
      })()
    JS

    def initialize(tab:)
      @tab = tab
    end

    def call
      {
        page: collect(PAGE_SCRIPT),
        fonts: collect(FONTS_SCRIPT),
        print_media: collect(PRINT_MEDIA_SCRIPT),
        paged_js: collect(PAGED_JS_SCRIPT)
      }
    end

    private

    def collect(script)
      response = @tab.execute_script(script)
      return nil unless response.is_a?(Hash) && response["type"] == "success"

      value = response.dig("result", "value")
      value ? JSON.parse(value) : nil
    rescue JSON::ParserError
      nil
    end
  end
end
