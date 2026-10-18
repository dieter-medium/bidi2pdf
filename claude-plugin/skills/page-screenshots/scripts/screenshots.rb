#!/usr/bin/env ruby
# frozen_string_literal: true

# Full-page screenshots of a site for design and accessibility review, through bidi2pdf: every page
# at every width, in light and dark mode, one PNG each - <out>/<page>-<width>-<scheme>.png.
#
#   ruby screenshots.rb --base http://app:4000 --pages /,/about --widths 360,1280 \
#     --out tmp/screenshots --remote-browser-url http://remote-chrome:3000/session
#
# Needs a bidi2pdf with BrowserTab#emulate_media (the release after 0.1.22). Without
# --remote-browser-url it starts a local chromedriver (Chrome must be installed).
require "optparse"
require "fileutils"
require "uri"
require "bidi2pdf"

options = { pages: ["/"], widths: [360, 1280], schemes: %w[light dark], height: 900, out: "tmp/screenshots" }
OptionParser.new do |parser|
  parser.banner = "Usage: screenshots.rb --base URL [options]"
  parser.on("--base URL", "Site to shoot, e.g. http://app:4000 (required)") { |value| options[:base] = value }
  parser.on("--pages LIST", Array, "Site-root-relative paths (default: /)") { |value| options[:pages] = value }
  parser.on("--widths LIST", Array, "Viewport widths in CSS px (default: 360,1280)") { |value| options[:widths] = value.map { |width| Integer(width) } }
  parser.on("--schemes LIST", Array, "light, dark or both (default: light,dark)") { |value| options[:schemes] = value }
  parser.on("--height N", Integer, "Viewport height in CSS px (default: 900; the shot is the whole page)") { |value| options[:height] = value }
  parser.on("--out DIR", "Output folder (default: tmp/screenshots)") { |value| options[:out] = value }
  parser.on("--remote-browser-url URL", "chromedriver new-session URL, e.g. http://remote-chrome:3000/session") { |value| options[:remote] = value }
end.parse!

abort "screenshots.rb: --base is required" unless options[:base]
bad = options[:schemes] - Bidi2pdf::Bidi::BrowserTab::EMULATED_MEDIA[:color_scheme]
abort "screenshots.rb: unknown scheme #{bad.join(", ")} (light, dark)" if bad.any?

def file_name(page, width, scheme)
  slug = page.delete_prefix("/").gsub(/[^A-Za-z0-9]+/, "-").delete_suffix("-")
  "#{slug.empty? ? "index" : slug}-#{width}-#{scheme}.png"
end

def open_session(remote)
  if remote
    session = Bidi2pdf::Bidi::Session.new(session_url: remote, headless: true, chrome_args: Bidi2pdf::Bidi::Session::DEFAULT_CHROME_ARGS,
                                          registry: Bidi2pdf::SessionRegistry.new(remote))
    session.start
    [session, nil]
  else
    manager = Bidi2pdf::ChromedriverManager.new(headless: true)
    manager.start
    [manager.session.tap(&:start), manager]
  end
end

Bidi2pdf.configure { |config| config.logger.level = Logger::ERROR }
FileUtils.mkdir_p(options[:out])
session, manager = open_session(options[:remote])
begin
  user_context = session.browser.create_user_context
  tab = user_context.create_browser_window.create_browser_tab
  options[:schemes].each do |scheme|
    tab.emulate_media(media: "screen", color_scheme: scheme)
    options[:widths].each do |width|
      tab.set_viewport(width: width, height: options[:height])
      options[:pages].each do |page|
        tab.navigate_to(URI.join(options[:base], page).to_s)
        tab.wait_until_network_idle
        path = File.join(options[:out], file_name(page, width, scheme))
        tab.screenshot(path)
        puts path
      end
    end
  end
ensure
  session&.close
  manager&.stop
end
