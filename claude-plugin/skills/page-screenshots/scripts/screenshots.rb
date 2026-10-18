#!/usr/bin/env ruby
# frozen_string_literal: true

# Full-page screenshots of a site for design and accessibility review, through bidi2pdf: every page
# at every width, in light and dark mode, one PNG each - <out>/<page path>-<width>-<scheme>.png.
#
#   ruby screenshots.rb --base http://app:4000 --pages /,/about --widths 360,1280 \
#     --out tmp/screenshots --remote-browser-url http://remote-chrome:3000/session
#
# Needs bidi2pdf 0.1.23 or later (BrowserTab#emulate_media). Without
# --remote-browser-url it starts a local chromedriver (Chrome must be installed).
require "digest"
require "fileutils"
require "optparse"
require "uri"
require "bidi2pdf"

module Screenshots
  # Letters, digits, "_" and "-": a part of a file path that cannot leave the output folder.
  SAFE_PART = /\A[A-Za-z0-9_-]+\z/

  module_function

  # The PNG's path below the output folder. The page's path stays a folder hierarchy, each part
  # letters, digits, "_" and "-" only, so nothing ever leaves the output folder; when a part had to
  # be changed (or the page has a query), a short hash of the original path keeps two pages apart
  # that would otherwise get the same name - "/a.b" and "/a-b", "/x?y=1" and "/x".
  def path_for(page, width, scheme)
    uri = URI.parse(page.to_s)
    parts = path_parts(uri)
    safe = parts.map { |part| safe_part(part) }
    safe[-1] = "#{safe[-1]}-#{Digest::SHA256.hexdigest(page.to_s)[0, 8]}" if uri.query || uri.fragment || safe != parts
    File.join(*safe[0..-2], "#{safe[-1]}-#{width}-#{scheme}.png")
  end

  # The page's path as folder names; a folder's own page ("/" or "/docs/") is its index.
  def path_parts(uri)
    parts = uri.path.to_s.split("/").reject(&:empty?)
    parts << "index" if parts.empty? || uri.path.end_with?("/")
    parts
  end

  def safe_part(part)
    clean = part.gsub(/[^A-Za-z0-9_-]+/, "-")
    clean.match?(SAFE_PART) ? clean : "page"
  end

  # Chrome's own sandbox off only where the CLI turns it off too (DISABLE_CHROME_SANDBOX=true, for a
  # container that does not grant it).
  def chrome_args
    args = Bidi2pdf::Bidi::Session::DEFAULT_CHROME_ARGS.dup
    args << "--no-sandbox" if ENV["DISABLE_CHROME_SANDBOX"] == "true"
    args
  end

  # A started browser session for the block, stopped afterwards - also when starting it failed
  # halfway, so no chromedriver or remote session is left running.
  def with_browser(remote)
    manager = nil
    if remote
      session = Bidi2pdf::Bidi::Session.new(session_url: remote, headless: true, chrome_args: chrome_args,
                                            registry: Bidi2pdf::SessionRegistry.new(remote))
    else
      manager = Bidi2pdf::ChromedriverManager.new(headless: true, chrome_args: chrome_args)
      manager.start
      session = manager.session
    end
    session.start
    yield session
  ensure
    begin
      session&.close
    ensure
      manager&.stop
    end
  end

  def shoot(options)
    with_browser(options[:remote]) do |session|
      tab = open_tab(session)
      options[:schemes].each do |scheme|
        tab.emulate_media(media: "screen", color_scheme: scheme)
        options[:widths].each do |width|
          tab.set_viewport(width: width, height: options[:height])
          options[:pages].each { |page| puts shoot_page(tab, options, page, width, scheme) }
        end
      end
    end
  end

  def open_tab(session) = session.browser.create_user_context.create_browser_window.create_browser_tab

  # One full-page shot; returns its path.
  def shoot_page(tab, options, page, width, scheme)
    tab.navigate_to(URI.join(options[:base], page).to_s)
    tab.wait_until_network_idle
    path = File.join(options[:out], path_for(page, width, scheme))
    FileUtils.mkdir_p(File.dirname(path))
    tab.screenshot(path)
    path
  end

  # flag, type, description, option key, and how to turn the value into the option.
  OPTIONS = [
    ["--base URL", String, "Site to shoot, e.g. http://app:4000 (required)", :base],
    ["--pages LIST", Array, "Site-root-relative paths (default: /)", :pages],
    ["--widths LIST", Array, "Viewport widths in CSS px (default: 360,1280)", :widths, ->(widths) { widths.map { |width| Integer(width) } }],
    ["--schemes LIST", Array, "light, dark or both (default: light,dark)", :schemes],
    ["--height N", Integer, "Viewport height in CSS px (default: 900; the shot is the whole page)", :height],
    ["--out DIR", String, "Output folder (default: tmp/screenshots)", :out],
    ["--remote-browser-url URL", String, "chromedriver new-session URL, e.g. http://remote-chrome:3000/session", :remote]
  ].freeze

  def parse_options(argv)
    options = { pages: ["/"], widths: [360, 1280], schemes: %w[light dark], height: 900, out: "tmp/screenshots" }
    OptionParser.new do |parser|
      parser.banner = "Usage: screenshots.rb --base URL [options]"
      OPTIONS.each do |flag, type, description, key, convert|
        parser.on(flag, type, description) { |value| options[key] = convert ? convert.call(value) : value }
      end
    end.parse!(argv)
    options
  end
end

if $PROGRAM_NAME == __FILE__
  options = Screenshots.parse_options(ARGV)
  abort "screenshots.rb: --base is required" unless options[:base]
  bad = options[:schemes] - Bidi2pdf::Bidi::BrowserTab::EMULATED_MEDIA[:color_scheme]
  abort "screenshots.rb: unknown scheme #{bad.join(", ")} (light, dark)" if bad.any?

  Bidi2pdf.configure { |config| config.logger.level = Logger::ERROR }
  Screenshots.shoot(options)
end
