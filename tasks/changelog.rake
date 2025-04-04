# frozen_string_literal: true

def cliff_installed?
  system("which git-cliff > /dev/null 2>&1")
end

namespace :changelog do
  desc "Generate unreleased section in CHANGELOG.md (requires git-cliff)"
  task :update_unreleased do
    unless cliff_installed?
      puts "🚫 git-cliff is not installed!"
      puts "👉 Install it here: https://git-cliff.org/docs/installation/"
      exit 1
    end

    generated = `git cliff --unreleased`

    changelog_path = "CHANGELOG.md"
    changelog = File.read(changelog_path)

    updated = changelog.sub(
      /<!--.*generated\s+by\s+git-cliff\s+start\s+-->(.*?)<!--\s+generated\s+by\s+git-cliff\s+end\s+-->/m,
      generated.strip
    )

    File.write(changelog_path, updated)
    puts "✅ Replaced generated section in CHANGELOG.md"
  end
end
