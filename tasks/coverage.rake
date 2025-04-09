# frozen_string_literal: true

namespace :coverage do
  desc "Merge simplecov coverage reports"
  task :merge_reports do
    require "simplecov"

    SimpleCov.collate Dir["coverage/*-resultset.json"] do
      formatter SimpleCov::Formatter::MultiFormatter.new([
                                                           SimpleCov::Formatter::SimpleFormatter,
                                                           SimpleCov::Formatter::HTMLFormatter,
                                                           SimpleCov::Formatter::JSONFormatter
                                                         ])
    end
  end
end
