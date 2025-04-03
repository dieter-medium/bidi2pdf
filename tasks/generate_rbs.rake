# frozen_string_literal: true

require "fileutils"
require "rbs"

SOURCE_DIR = "lib"
OUTPUT_DIR = "sig"

# rubocop:disable  Metrics/BlockLength
namespace :rbs do
  file_list = FileList["#{SOURCE_DIR}/**/*.rb"]

  desc "Generate all RBS files"
  task generate_rbs: :rbs_targets

  rbs_map = file_list.to_h do |rb|
    relative = rb.sub(%r{^#{SOURCE_DIR}/}, "")
    rbs = File.join(OUTPUT_DIR, relative.sub(/\.rb$/, ".rbs"))
    [rbs, rb]
  end

  rbs_map.each do |rbs_path, rb_path|
    file rbs_path => rb_path do
      puts "🔧 Generating: #{rbs_path} (from #{rb_path})"

      FileUtils.mkdir_p(File.dirname(rbs_path))

      begin
        input = Pathname(rb_path)
        output = Pathname(rbs_path)

        parser = RBS::Prototype::RB.new
        parser.parse input.read

        if output.file?
          puts "⚠️  RBS file already exists: #{rbs_path}"
        else
          puts "📝 Writing RBS file: #{rbs_path}"

          output.open("w") do |io|
            writer = RBS::Writer.new(out: io)
            writer.write(parser.decls)
          end
        end
      rescue StandardError => e
        puts "❌ Error generating RBS for #{rb_path}: #{e.message}"
      end
    end
  end

  desc "Generate RBS files for all Ruby files"
  task rbs_targets: rbs_map.keys do
    puts "✅ RBS generation complete!"
  end

  desc "Clean all generated RBS files"
  task :clean_rbs do
    FileList["#{OUTPUT_DIR}/**/*.rbs"].each do |file|
      FileUtils.rm_f(file)
    end
    puts "🧹 Cleaned up all RBS files"
  end
end
# rubocop:enable Metrics/BlockLength
