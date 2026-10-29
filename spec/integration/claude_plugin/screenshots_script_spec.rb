# frozen_string_literal: true

require "spec_helper"
require "open3"
require "rbconfig"
require "tmpdir"

# The page-screenshots skill's script run for real, as an agent runs it: a subprocess against the
# suite's Chrome and nginx containers. Its naming and cleanup are unit-tested in
# spec/unit/claude_plugin/screenshots_script_spec.rb.
RSpec.describe "The page-screenshots script", :chromedriver, :nginx do # rubocop:disable RSpec/DescribeClass
  def script = File.expand_path("../../../claude-plugin/skills/page-screenshots/scripts/screenshots.rb", __dir__)

  def run_script(out, *)
    Open3.capture2e(RbConfig.ruby, "-I", File.expand_path("../../../lib", __dir__), script,
                    "--base", nginx_url("", use_alias: true), "--remote-browser-url", session_url, "--out", out, *)
  end

  # The width of a PNG, from its IHDR chunk.
  def png_width(path) = File.binread(path, 24).unpack1("@16N")

  # A full-page shot is as wide as the document, so only a page that fits into 360 px comes out at 360: sample.html
  # (Paged.js, A4 sheets, 794 px once laid out) and sample-without-page-settings.html (a table, 386 px) do not - both
  # failed this on CI for PR #184. simple.html has nothing wider; its second address (a query) is a page of its own
  # to the script and gets a name of its own.
  it "writes one shot per page, width and scheme, at the width asked for" do
    Dir.mktmpdir do |out|
      _output, status = run_script(out, "--pages", "/simple.html,/simple.html?view=second", "--widths", "360", "--schemes", "light,dark")
      shots = Dir[File.join(out, "**", "*.png")]

      expect([status.success?, shots.size, shots.map { |shot| png_width(shot) }.uniq]).to eq([true, 4, [360]])
    end
  end

  it "prints each shot's path" do
    Dir.mktmpdir do |out|
      output, = run_script(out, "--pages", "/simple.html", "--widths", "360", "--schemes", "dark")

      expect(output.lines.map(&:strip).grep(/\.png\z/)).to eq(Dir[File.join(out, "**", "*.png")])
    end
  end
end
