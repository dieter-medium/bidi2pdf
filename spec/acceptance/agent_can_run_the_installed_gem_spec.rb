# frozen_string_literal: true

require "spec_helper"
require "open3"
require "json"
require "rbconfig"

# Under `bundle exec` Bundler evaluates bidi2pdf.gemspec, which loads lib/bidi2pdf/version.rb - so every other spec
# has Bidi2pdf::VERSION whether the library loads it or not. An installed gem never evaluates its gemspec: 0.1.24
# failed `bidi2pdf version` and every `render --manifest` with "uninitialized constant Bidi2pdf::VERSION". This runs
# the executable without Bundler, with only the load path it would have found, like `gem install bidi2pdf` gives.
RSpec.feature "As an LLM agent, I want the installed gem to report its version", :acceptance do
  def bidi2pdf_without_bundler(*)
    root = File.expand_path("../..", __dir__)
    env = { "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil, "BUNDLER_SETUP" => nil, "RUBYLIB" => $LOAD_PATH.join(File::PATH_SEPARATOR) }
    out, _err, status = Open3.capture3(env, RbConfig.ruby, "--disable-gems", File.join(root, "exe", "bidi2pdf"), *, chdir: root)
    [status.exitstatus, out]
  end

  scenario "Asking for the version before the first render" do
    when_ "I run bidi2pdf version --json from the installed gem" do
      before { @status, @stdout = bidi2pdf_without_bundler("version", "--json") }

      then_ "it answers with the gem's version and exits 0" do
        expect([@status, JSON.parse(@stdout)["bidi2pdf"]]).to eq([0, Bidi2pdf::VERSION])
      end
    end
  end
end
