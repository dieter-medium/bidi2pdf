# frozen_string_literal: true

require "spec_helper"
require "cgi"
require "bidi2pdf/cli"

# The landing page and llms.txt in site/ (published by .github/workflows/pages.yml) tell search engines and agents
# what bidi2pdf does. Every command, option, exit code and README section they name is checked against the gem and
# the README, so renaming one fails here instead of misleading a reader.
RSpec.describe "The landing page" do # rubocop:disable RSpec/DescribeClass
  def root = File.expand_path("../..", __dir__)

  def command_names = Bidi2pdf::CLI.all_commands.keys + Bidi2pdf::CLI.map.keys.map(&:to_s)

  # A command's flags as a user can type them: dashed and underscored, its --no-/--skip- forms, and its aliases.
  def flags_of(command)
    (command.options.values + Bidi2pdf::CLI.class_options.values).flat_map do |option|
      name = option.switch_name.tr("_", "-")
      forms = [name, *option.aliases.map { |flag| flag.tr("_", "-") }]
      option.boolean? ? forms + [name.sub("--", "--no-"), name.sub("--", "--skip-")] : forms
    end
  end

  def every_flag = Bidi2pdf::CLI.all_commands.values.flat_map { |command| flags_of(command) }.uniq

  # GitHub's anchor for a heading: lower case, everything but letters, digits, spaces, hyphens and underscores
  # dropped, spaces turned into hyphens.
  def readme_anchors
    File.read(File.join(root, "README.md")).scan(/^#+ (.+)$/).flatten
        .map { |heading| heading.downcase.gsub(/[^\p{Alnum} _-]/, "").tr(" ", "-") }
  end

  def exit_codes = Bidi2pdf::ExitCodes.constants.map { |name| Bidi2pdf::ExitCodes.const_get(name) }.grep(Integer).sort

  { "index.html" => %r{<code>(.*?)</code>}m, "llms.txt" => /`([^`]+)`/ }.each do |name, code_span|
    describe name do
      let(:text) { File.read(File.join(root, "site", name)) }
      let(:code) { text.scan(code_span).flatten.map { |span| CGI.unescapeHTML(span) }.join("\n") }

      it "names only commands bidi2pdf has" do
        expect(code.scan(/\bbidi2pdf ([a-z_-]+)/).flatten.uniq - command_names).to eq([])
      end

      it "shows only options some command takes" do
        flags = code.scan(/(?<![\w-])--[a-z][a-z0-9_-]*/).map { |flag| flag.tr("_", "-") }.uniq

        expect(flags - every_flag).to eq([])
      end

      it "lists the exit codes bidi2pdf uses, no more and no fewer" do
        listed = name == "index.html" ? text.scan(%r{<td><code>(\d+)</code></td>}) : text[/Exit codes: ([^.]+)\./, 1].to_s.scan(/(\d+) [A-Za-z]/)

        expect(listed.flatten.map { |code| Integer(code) }.sort).to eq(exit_codes)
      end

      it "links only to README sections that exist" do
        anchors = text.scan(%r{github\.com/dieter-medium/bidi2pdf#([a-z0-9_-]+)}).flatten - ["readme"]

        expect(anchors - readme_anchors).to eq([])
      end
    end
  end
end
