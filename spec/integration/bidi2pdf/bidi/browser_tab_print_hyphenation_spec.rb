# frozen_string_literal: true

require "spec_helper"

# `hyphens: auto` needs Chromium's hyphenation dictionaries, which Debian's chromium does not ship and
# which Chrome cannot download in the container (docker/install-hyphen-data.sh). Without them Chrome
# silently falls back to `hyphens: manual` - no error, no console message, just unbroken words - so
# this is checked on the actual image: in CI the one built from this checkout
# (BIDI2PDF_BUILD_CHROMEDRIVER_IMAGE, ChromedriverContainer.build_locally?), elsewhere the published one.
RSpec.describe Bidi2pdf::Bidi::BrowserTab, "#print", :chromedriver, :session do
  # Blink breaks words at the dictionary's hyphenation points and prints U+2010 HYPHEN at the break,
  # or "-" when the font has no U+2010 glyph; pdf-reader ends the line after it.
  let(:hyphen_break) { /[-‐]\n\s*/ }
  let(:german_word) { "Donaudampfschifffahrtsgesellschaftskapitän" }

  # Every language the image promises (README "Hyphenation"), by the `lang` tag Blink maps to each
  # dictionary, with a word far wider than the 120 px box - it fits only when broken inside. Checked
  # on the published image 2026-10-03, one fresh session each.
  cases = {
    "de" => "Donaudampfschifffahrtsgesellschaftskapitän",
    "de-1901" => "Donaudampfschiffahrtsgesellschaftskapitän",
    "de-CH-1901" => "Donaudampfschiffahrtsgesellschaftskapitän",
    "en" => "internationalization",
    "en-GB" => "internationalisation",
    "fr" => "anticonstitutionnellement",
    "es" => "electroencefalografista",
    "it" => "precipitevolissimevolmente",
    "nl" => "arbeidsongeschiktheidsverzekering",
    "pt" => "inconstitucionalissimamente"
  }

  def document(lang:, word:, hyphens:)
    <<~HTML
      <!DOCTYPE html>
      <html lang="#{lang}">
        <head>
          <meta charset="utf-8">
          <style>
            body { font-family: "Liberation Serif", serif; font-size: 16px; }
            .text { width: 120px; hyphens: #{hyphens}; }
          </style>
        </head>
        <body><p class="text">#{word}</p></body>
      </html>
    HTML
  end

  # What one print shows about a word, as one value - each print is a real render, so an example checks
  # all of it at once: broken at a hyphen, still whole somewhere, whole again once rejoined.
  def shape(text, word)
    { broken: text.match?(hyphen_break), whole: text.include?(word), rejoined: text.gsub(hyphen_break, "").include?(word) }
  end

  def print_text(html)
    with_tab(session_url) do |tab|
      tab.render_html_content(html)
      pdf = tab.print

      Bidi2pdf::TestHelpers::PDFReaderUtils.pdf_text(pdf).join("\n")
    end
  end

  # Rejoined, the pieces are the whole word again: it was broken at hyphenation points, not cut,
  # wrapped or dropped - and the whole word appears nowhere else.
  cases.each do |lang, word|
    it "hyphenates with hyphens: auto and lang=#{lang}" do
      text = print_text(document(lang: lang, word: word, hyphens: "auto"))

      expect(shape(text, word)).to eq(broken: true, whole: false, rejoined: true)
    end
  end

  # Guards the assertions above: the same document without `hyphens: auto` must keep the word in one
  # piece, or the checks would pass on an image that never hyphenates anything.
  it "leaves the word whole with hyphens: manual" do
    text = print_text(document(lang: "de", word: german_word, hyphens: "manual"))

    expect(shape(text, german_word)).to eq(broken: false, whole: true, rejoined: true)
  end
end
