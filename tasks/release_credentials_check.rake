# frozen_string_literal: true

require "yaml"

# Works out which rubygems.org credential `rake release` would really push with, and refuses to go on
# when that is not what the repo's configuration says it should be.
module ReleaseCredentialsCheck
  BUNDLE_CONFIG_PATH = ".bundle/config"
  CREDENTIALS_PATH = File.expand_path("~/.gem/credentials")

  module_function

  # Ask Bundler, exactly as its own release task does (gem_helper.rb: Bundler.settings["gem.push_key"])
  # - never parse .bundle/config for this. Bundler may not be reading that file at all: the official
  # ruby Docker images set BUNDLE_APP_CONFIG=/usr/local/bundle, which silently replaces the repo's
  # .bundle/ as the app config dir. Reading the file directly made this check report a key that
  # `rake release` then did not use.
  def effective_key
    Bundler.settings["gem.push_key"]&.to_s&.downcase
  end

  # What the repo's own .bundle/config asks for - only ever compared against #effective_key.
  def key_on_disk
    return unless File.exist?(BUNDLE_CONFIG_PATH)

    (YAML.load_file(BUNDLE_CONFIG_PATH) || {})["BUNDLE_GEM__PUSH_KEY"]&.to_s&.downcase
  end

  def available_keys
    File.exist?(CREDENTIALS_PATH) ? (YAML.load_file(CREDENTIALS_PATH) || {}).keys.map(&:to_s) : []
  end

  # Always printed first, in one stream (puts only - mixing in `warn`'s stderr made lines print out
  # of order once a terminal merges the two streams), so the context stays visible above whichever
  # message stops the release.
  def print_banner(key, keys)
    puts "=== rubygems.org push credentials ==="
    puts "  gem.push_key Bundler will use: #{key || "(not set)"}"
    puts "  Bundler app config dir:        #{Bundler.app_config_path}#{" (from BUNDLE_APP_CONFIG)" if ENV["BUNDLE_APP_CONFIG"]}"
    puts "  ~/.gem/credentials keys:       #{keys.empty? ? "(none found)" : keys.join(", ")}"
    puts "======================================"
  end

  # @return [String, nil] why the release must not go on, or nil when it may
  def problem(key, keys)
    ignored_config_problem(key) || credentials_problem(key, keys)
  end

  def ignored_config_problem(key)
    wanted = key_on_disk
    return if wanted.nil? || wanted == key

    "#{BUNDLE_CONFIG_PATH} sets gem.push_key '#{wanted}', but Bundler is not reading that file " \
      "(app config dir: #{Bundler.app_config_path}) and would push with '#{key || "the default rubygems_api_key"}'. " \
      "Set BUNDLE_GEM__PUSH_KEY=#{wanted} in the environment, or unset BUNDLE_APP_CONFIG."
  end

  def credentials_problem(key, keys)
    return "~/.gem/credentials has no keys at all (missing, empty, or not mounted)." if keys.empty?
    return "configured key '#{key}' is not among ~/.gem/credentials' keys #{keys.inspect}." if key && !keys.include?(key)
    return if key || keys.include?("rubygems_api_key")

    "no gem.push_key configured and ~/.gem/credentials has no default 'rubygems_api_key' key (found: #{keys.inspect})."
  end
end

desc "Show which rubygems.org credential key `rake release`/`gem push` will use"
task :release_credentials_check do
  # Without this, stdout is buffered (not a TTY once piped/captured) while stderr isn't - so
  # `abort`'s message below can reach the terminal before the `puts` lines that logically ran
  # first, once the two streams get merged. Confirmed live: without sync, "release aborted: ..."
  # printed above the diagnostic banner, not after it.
  $stdout.sync = true

  key = ReleaseCredentialsCheck.effective_key
  keys = ReleaseCredentialsCheck.available_keys
  ReleaseCredentialsCheck.print_banner(key, keys)

  problem = ReleaseCredentialsCheck.problem(key, keys)
  abort "release aborted: #{problem}" if problem

  puts "NOTE: no gem.push_key configured - this will push using the default :rubygems_api_key." if key.nil?
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
