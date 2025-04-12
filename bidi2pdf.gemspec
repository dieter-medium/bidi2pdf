# frozen_string_literal: true

require_relative "lib/bidi2pdf/version"

Gem::Specification.new do |spec|
  spec.name = "bidi2pdf"
  spec.version = Bidi2pdf::VERSION
  spec.authors = ["Dieter S."]
  spec.email = ["101627195+dieter-medium@users.noreply.github.com"]

  spec.summary = "A Ruby gem that generates PDFs from web pages using Chrome's BiDi protocol, providing high-quality PDF documents from any URL with full support for modern web features."
  # rubocop:enable Layout/LineLength
  spec.description = <<~DESC
    Bidi2pdf is a powerful PDF generation tool that uses Chrome's BiDirectional Protocol
    to render web pages as high-quality PDF documents. It offers:

    * Command-line interface for easy PDF generation
    * Support for cookies, headers, and basic authentication
    * Waiting conditions (window loaded, network idle)
    * Headless Chrome operation for server environments
    * Docker compatibility
    * Customizable PDF output options

    Bidi2pdf uses ChromeDriver to control Chrome through its BiDi protocol, providing
    precise rendering for reports, invoices, documentation, and other PDF documents
    from web-based content. It automatically manages the ChromeDriver binary and browser
    sessions for a seamless experience.
  DESC
  spec.homepage = "https://github.com/dieter-medium/bidi2pdf"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/master/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"
  spec.add_dependency "base64", "~> 0.2.0"
  spec.add_dependency "chromedriver-binary"
  spec.add_dependency "json", "~> 2.10"
  spec.add_dependency "rubyzip", "~> 2.4"
  spec.add_dependency "sys-proctable", "~> 1.3"
  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "websocket-client-simple", "~> 0.9.0"

  spec.add_development_dependency "diff-lcs", "~> 1.5"
  spec.add_development_dependency "pdf-reader", "~> 2.14"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rbs", "~> 3.4"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.21"
  spec.add_development_dependency "rubocop-rake", "~> 0.7"
  spec.add_development_dependency "rubocop-rspec", "~> 3.5"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "testcontainers", "~> 0.2"
  spec.add_development_dependency "testcontainers-nginx", "~> 0.2"
  spec.add_development_dependency "unicode_utils", "~> 1.4"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
  spec.metadata["rubygems_mfa_required"] = "true"
end
