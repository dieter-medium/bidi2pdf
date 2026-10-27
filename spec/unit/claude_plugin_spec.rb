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
    # Claude Code reads a plugin version as semver, so the gem's "0.1.23.pre" is spelled "0.1.23-pre".
    it "names the plugin bidi2pdf, at the gem's own version in semver spelling" do
      manifest = JSON.parse(File.read(File.join(plugin_dir, ".claude-plugin", "plugin.json")))

      expect(manifest.values_at("name", "version")).to eq(["bidi2pdf", Bidi2pdf::VERSION.sub(/\.(?=[a-z])/, "-")])
    end

    it "lists the plugin in the repository's marketplace, at a folder that holds it" do
      marketplace = JSON.parse(File.read(File.join(root, ".claude-plugin", "marketplace.json")))
      sources = marketplace.fetch("plugins").map { |plugin| File.join(root, plugin.fetch("source"), ".claude-plugin", "plugin.json") }

      expect(sources.select { |path| File.file?(path) }).to eq(sources)
    end

    # The developer portal takes it as the listing icon once, the first time the plugin is saved or submitted: a
    # square PNG or JPEG of 512 to 2048 px a side, under 2 MB (no SVG, no WebP). A PNG's size sits in its IHDR chunk.
    it "has a listing icon the developer portal accepts: a square PNG of 512 to 2048 px, under 2 MB" do
      bytes = File.binread(File.join(plugin_dir, ".claude-plugin", "icon.png"))
      width, height = bytes[16, 8].unpack("NN")

      expect([bytes.start_with?("\x89PNG\r\n\x1A\n".b), width == height, (512..2048).cover?(width), bytes.bytesize < 2 * 1024 * 1024])
        .to eq([true, true, true, true])
    end

    # Codex reads the same plugin folder through its portable manifest (Agent Plugins 1.0.0, plugin.json at the
    # plugin root, OpenAI's listing under extensions.com.openai.interface) and the repository's
    # .agents/plugins/marketplace.json. Limits from developers.openai.com/plugins/deploy/submission.
    describe "for Codex" do
      def portable = JSON.parse(File.read(File.join(plugin_dir, "plugin.json")))

      def listing = portable.dig("extensions", "com.openai", "interface")

      # WCAG relative luminance of a #RRGGBB colour.
      def luminance(hex)
        hex.delete("#").scan(/../).map { |pair| Integer(pair, 16) / 255.0 }
           .map { |c| c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4 }
           .zip([0.2126, 0.7152, 0.0722]).sum { |c, weight| c * weight }
      end

      it "names the same plugin at the same version as the Claude Code manifest" do
        claude = JSON.parse(File.read(File.join(plugin_dir, ".claude-plugin", "plugin.json")))

        expect(portable.values_at("$schema", "name", "version", "description"))
          .to eq(["https://agent-plugins.org/schemas/1.0.0/plugin.schema.json", *claude.values_at("name", "version", "description")])
      end

      it "has a name the Agent Plugins schema accepts" do
        expect(portable["name"]).to match(/\A(?!.*(?:--|\.\.))[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\z/)
      end

      it "keeps the listing within the directory's limits" do
        lengths = listing.values_at("displayName", "shortDescription", "longDescription", "developerName").map { |text| text.to_s.length }

        expect(lengths.zip([30, 30, 4000, 80]).reject { |length, limit| length.between?(1, limit) }).to eq([])
      end

      it "offers at most three distinct prompts of at most 128 characters, without @-mentions" do
        prompts = Array(listing["defaultPrompt"])

        expect([prompts.size <= 3, prompts.uniq == prompts, prompts.all? { |prompt| prompt.length <= 128 && !prompt.include?("@") }])
          .to eq([true, true, true])
      end

      it "names a category and at most 20 capabilities of at most 120 characters" do
        capabilities = listing["capabilities"]

        expect([listing["category"].to_s.empty?, capabilities.is_a?(Array) && capabilities.size <= 20 && capabilities.all? { |c| c.length <= 120 }])
          .to eq([false, true])
      end

      it "has a brand colour with at least 2:1 contrast against white" do
        color = listing["brandColor"]

        expect([color.match?(/\A#\h{6}\z/), (1.05 / (luminance(color) + 0.05)).round(2) >= 2.0]).to eq([true, true])
      end

      it "points composerIcon and logo at square PNGs inside the plugin, 48 to 4096 px, at most 5 MiB" do
        wrong = listing.values_at("composerIcon", "logo").reject do |path|
          file = File.expand_path(path, plugin_dir)
          bytes = File.file?(file) ? File.binread(file) : ""
          width, height = bytes[16, 8].to_s.unpack("NN")
          path.start_with?("./") && !path.include?("..") && file.start_with?("#{plugin_dir}/") &&
            bytes.start_with?("\x89PNG\r\n\x1A\n".b) && width == height && (48..4096).cover?(width.to_i) && bytes.bytesize <= 5 * 1024 * 1024
        end

        expect(wrong).to eq([])
      end

      it "is listed in the repository's Codex marketplace, for Codex only, at a folder that holds it" do
        marketplace = JSON.parse(File.read(File.join(root, ".agents", "plugins", "marketplace.json")))
        entries = marketplace.fetch("plugins").map do |plugin|
          [File.file?(File.join(root, plugin.dig("source", "path"), "plugin.json")), plugin.dig("policy", "products")]
        end

        expect(entries).to eq([[true, ["CODEX"]]])
      end
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

  # No agent guarantees a SKILL_DIR variable (Codex exports none): an example that uses it must set it first,
  # or a copied command looks for /scripts/... at the file system root.
  it "sets SKILL_DIR in every example before using it" do
    unset = skill_files.flat_map do |path|
      fenced_blocks(File.read(path), "bash").filter_map do |block|
        first_use = block.index("$SKILL_DIR") or next
        assignment = block =~ /^\s*(?:export\s+)?SKILL_DIR=/
        "#{File.basename(File.dirname(path))}: #{block.lines.first.strip}" unless assignment && assignment < first_use
      end
    end

    expect(unset).to eq([])
  end

  # A Codex run without Ruby tried to install it from the system, printed with Chromium directly when bidi2pdf failed,
  # and installed Poppler to count pages. Each skill may be loaded alone, so each carries the same rules against that.
  describe "ground rules" do
    def section(text, heading) = text[/^## #{Regexp.escape(heading)}\n.*?(?=^## )/m]

    def render_pdf = File.read(File.join(plugin_dir, "skills", "render-pdf", "SKILL.md"))

    def foreign_command
      Regexp.union(
        /\b(?:apt(?:-get)?|apk|yum|dnf|brew|pacman|pip3?|npm|npx)\s+(?:install|add)\b/,
        /\b(?:pdfinfo|pdftotext|pdftoppm|mutool|wkhtmltopdf)\b/,
        /\b(?:chrom(?:e|ium)[\w-]*|google-chrome)\b.*--(?:headless|print-to-pdf)/
      )
    end

    it "carries the same ground rules in every skill" do
      rules = skill_files.map { |path| section(File.read(path), "Ground rules") }

      expect([rules.none?(&:nil?), rules.uniq.size]).to eq([true, 1])
    end

    # The one place that shows install commands is render-pdf's preflight, and only as suggestions to confirm.
    it "shows install commands only in render-pdf's preflight, never another PDF tool or Chrome printing by itself" do
      offending = skill_files.flat_map do |path|
        text = File.read(path)
        text = text.sub(section(text, "1. Preflight"), "") if path.end_with?("render-pdf/SKILL.md")
        (shell_lines(text) + text.scan(/`([^`\n]+)`/).flatten).grep(foreign_command).map { |line| "#{File.basename(File.dirname(path))}: #{line}" }
      end

      expect(offending).to eq([])
    end

    it "has the preflight suggest installs for the user to confirm, without other PDF tools" do
      preflight = section(render_pdf, "1. Preflight")

      expect([preflight.include?("only after a yes"), preflight.match?(/pdfinfo|poppler|wkhtmltopdf|print-to-pdf/i)]).to eq([true, false])
    end

    it "renders before it diagnoses in the render-pdf skill" do
      lines = shell_lines(render_pdf)

      expect(lines.index { |line| line.start_with?("bidi2pdf render") }).to be < lines.index { |line| line.start_with?("bidi2pdf diagnose") }
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
