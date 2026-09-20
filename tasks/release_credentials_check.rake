# frozen_string_literal: true

require "yaml"

desc "Show which rubygems.org credential key `rake release`/`gem push` will use"
task :release_credentials_check do
  # Without this, stdout is buffered (not a TTY once piped/captured) while stderr isn't - so
  # `abort`'s message below can reach the terminal before the `puts` lines that logically ran
  # first, once the two streams get merged. Confirmed live: without sync, "release aborted: ..."
  # printed above the diagnostic banner, not after it.
  $stdout.sync = true

  bundle_config_path = ".bundle/config"
  credentials_path = File.expand_path("~/.gem/credentials")

  configured_key = File.exist?(bundle_config_path) ? (YAML.load_file(bundle_config_path) || {})["BUNDLE_GEM__PUSH_KEY"] : nil
  available_keys = File.exist?(credentials_path) ? (YAML.load_file(credentials_path) || {}).keys.map(&:to_s) : []

  # Always print the full picture first, unconditionally, in one stream (puts only - mixing in
  # `warn`'s stderr here made lines print out of order once a terminal merges the two streams).
  # Only then decide whether to abort - the diagnostic context stays visible above whichever
  # message actually stops the release.
  puts "=== rubygems.org push credentials ==="
  puts "  .bundle/config gem.push_key: #{configured_key || "(not set)"}"
  puts "  ~/.gem/credentials keys:     #{available_keys.empty? ? "(none found)" : available_keys.join(", ")}"
  puts "======================================"

  abort "release aborted: ~/.gem/credentials has no keys at all (missing, empty, or not mounted)." if available_keys.empty?

  if configured_key.nil?
    puts "NOTE: no gem.push_key configured - this will push using the default :rubygems_api_key."
  elsif !available_keys.include?(configured_key)
    abort "release aborted: configured key '#{configured_key}' is not among ~/.gem/credentials' keys #{available_keys.inspect}."
  end
end

# A prerequisite of "release:rubygem_push" specifically, not the outer "release" task. Bundler's
# own gem_helper.rb defines release as depending on
# ["build", "release:guard_clean", "release:source_control_push", "release:rubygem_push"], run in
# that listed order, with release:rubygem_push's own action being the actual `rubygem_push(...)`
# call that consumes this credential - attaching to the outer "release" task instead would append
# here via Task#enhance's simple union, running this *after* every one of those, including the
# push itself, which would make it a report on a mistake already made, not a guard against one.
# Attaching to "release:rubygem_push" guarantees Rake resolves this before *that* task's own
# action runs, regardless of how bundler orders its other prerequisites in some other version -
# automatically, regardless of how `rake release` gets invoked (this Makefile's release-shell, a
# bare host checkout, CI), not something you have to remember to check with a separate command.
desc "Push the built gem to rubygems.org (checks credentials first)"
task "release:rubygem_push" => :release_credentials_check
