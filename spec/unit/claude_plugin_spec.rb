# frozen_string_literal: true

require "spec_helper"
require "json"
require "open3"
require "rbconfig"
require "yaml"
require "bidi2pdf/cli"

# The Claude Code plugin in claude-plugin/ (docs/plans/claude-skills.md) tells agents which commands,
# options, recipe steps and Ruby methods to use. Everything it names is checked against the gem
# itself, so renaming an option or an error code fails here instead of misleading an agent.
RSpec.describe "The Claude Code plugin" do # rubocop:disable RSpec/DescribeClass
  def root = File.expand_path("../..", __dir__)

  def plugin_dir = File.join(root, "claude-plugin")

  def skill_files = Dir[File.join(plugin_dir, "skills", "*", "SKILL.md")]

  # Flags in a skill's prose that belong to another tool, not to bidi2pdf.
  def other_tools_flags = %w[--cap-add]

  def fenced_blocks(text, language)
    text.scan(/^```#{language}\n(.*?)^```/m).flatten
  end

  # A shell block's commands, with backslash-continued lines joined.
  def shell_lines(text)
    fenced_blocks(text, "bash").flat_map { |block| block.gsub("\\\n", " ").lines.map(&:strip) }
  end

  # Every `bidi2pdf <command> ...` a skill shows, from its shell blocks and its inline code.
  def bidi2pdf_calls(text)
    inline = text.scan(/`(bidi2pdf [^`]+)`/).flatten
    (shell_lines(text) + inline).filter_map { |line| line[/(?:^|[\s|])(bidi2pdf\s+[a-z][a-z_-]*.*)/, 1] }
  end

  def flags(text) = text.scan(/(?<![\w-])--[a-z][a-z0-9_-]*/).map { |flag| flag.tr("_", "-") }

  def command_names = Bidi2pdf::CLI.all_commands.keys + Bidi2pdf::CLI.map.keys.map(&:to_s)

  def command_for(name) = Bidi2pdf::CLI.all_commands[Bidi2pdf::CLI.map.fetch(name, name).to_s]

  # A command's flags as a user can type them: dashed, its --no-/--skip- forms, and its aliases.
  def flags_of(command)
    (command.options.values + Bidi2pdf::CLI.class_options.values).flat_map do |option|
      name = option.switch_name.tr("_", "-")
      forms = [name, *option.aliases.map { |flag| flag.tr("_", "-") }]
      option.boolean? ? forms + [name.sub("--", "--no-"), name.sub("--", "--skip-")] : forms
    end
  end

  def every_flag = Bidi2pdf::CLI.all_commands.values.flat_map { |command| flags_of(command) }.uniq

  def frontmatter(text) = YAML.safe_load(text[/\A---\n(.*?)\n---\n/m, 1].to_s) || {}

  describe "manifests" do
    it "names the plugin bidi2pdf, at the gem's own version" do
      manifest = JSON.parse(File.read(File.join(plugin_dir, ".claude-plugin", "plugin.json")))

      expect(manifest.values_at("name", "version")).to eq(["bidi2pdf", Bidi2pdf::VERSION])
    end

    it "lists the plugin in the repository's marketplace, at a folder that holds it" do
      marketplace = JSON.parse(File.read(File.join(root, ".claude-plugin", "marketplace.json")))
      sources = marketplace.fetch("plugins").map { |plugin| File.join(root, plugin.fetch("source"), ".claude-plugin", "plugin.json") }

      expect(sources.select { |path| File.file?(path) }).to eq(sources)
    end

    it "has skills" do
      expect(skill_files.map { |path| File.basename(File.dirname(path)) }).to include("render-pdf", "pdf-recipe")
    end
  end

  Dir[File.expand_path("../../claude-plugin/skills/*/SKILL.md", __dir__)].each do |skill_path|
    describe "the #{File.basename(File.dirname(skill_path))} skill" do
      let(:path) { skill_path }
      let(:skill) { File.basename(File.dirname(path)) }
      let(:text) { File.read(path) }

      it "is named after its folder, with a description that says when to use it" do
        meta = frontmatter(text)

        expect([meta["name"], meta["description"].to_s.start_with?("This skill should be used when")]).to eq([skill, true])
      end

      it "names only commands bidi2pdf has" do
        unknown = bidi2pdf_calls(text).map { |call| call.split[1] }.uniq - command_names

        expect(unknown).to eq([])
      end

      it "gives every command only options that command takes" do
        wrong = bidi2pdf_calls(text).flat_map do |call|
          command = command_for(call.split[1])
          command ? (flags(call) - flags_of(command)).map { |flag| "#{call.split[1]} #{flag}" } : []
        end

        expect(wrong.uniq).to eq([])
      end

      it "mentions only options some command takes" do
        prose = text.gsub(/^```.*?^```/m, "")

        expect((flags(prose) - every_flag - other_tools_flags).uniq).to eq([])
      end

      it "maps each error code it lists to the exit code bidi2pdf gives it" do
        rows = text.scan(/^\| `([A-Z_]+)` \| (\d+) \|/)

        expect(rows.reject { |code, exit| Bidi2pdf::ExitCodes::CODE_TO_EXIT[code] == Integer(exit) }).to eq([])
      end

      it "shows only recipes the validator accepts" do
        recipes = fenced_blocks(text, "yaml").select { |block| block.start_with?("version:") }
        refused = recipes.filter_map do |block|
          Bidi2pdf::Recipe.new(YAML.safe_load(block)).validate!
          nil
        rescue Bidi2pdf::InvalidRecipeError => e
          e.message
        end

        expect(refused).to eq([])
      end

      it "calls only BrowserTab methods that exist" do
        called = text.scan(/\btab\.([a-z_]+[?!]?)/).flatten.uniq

        expect(called - Bidi2pdf::Bidi::BrowserTab.public_instance_methods.map(&:to_s)).to eq([])
      end

      it "requires only files the gem ships" do
        required = text.scan(/require "(bidi2pdf[^"]*)"/).flatten.uniq

        expect(required.reject { |file| File.file?(File.join(root, "lib", "#{file}.rb")) }).to eq([])
      end
    end
  end

  describe "the page-screenshots script" do
    let(:script) { File.join(plugin_dir, "skills", "page-screenshots", "scripts", "screenshots.rb") }

    it "takes every option its skill shows" do
      help, = Open3.capture2e(RbConfig.ruby, "-I", File.join(root, "lib"), script, "--help")
      shown = shell_lines(File.read(File.join(plugin_dir, "skills", "page-screenshots", "SKILL.md")))
              .grep(/screenshots\.rb/).flat_map { |line| flags(line) }

      expect(shown.uniq - flags(help)).to eq([])
    end
  end
end
