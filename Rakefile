# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

task default: %i[spec rubocop]

require "chromedriver/binary"
load "chromedriver/Rakefile"

Dir.glob("tasks/*.rake").each { |r| load r }

desc "Run tests with coverage"
task :coverage do
  ENV["COVERAGE"] = "true"
  Rake::Task["spec"].execute
  puts "Coverage report generated in coverage/ directory"
end
