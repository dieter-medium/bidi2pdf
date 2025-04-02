# frozen_string_literal: true

require "sys/proctable"
module Bidi2pdf
  class ProcessTree
    include Sys

    def initialize(root_pid = nil)
      @root_pid = root_pid
      @process_map = build_process_map
      connect_children
    end

    def children(of_pid)
      return [] unless @process_map[of_pid]

      direct_children = @process_map[of_pid][:children].map do |child_pid|
        @process_map[child_pid][:info]
      end

      (direct_children + direct_children.flat_map { |child| children(child.pid) }).uniq
    end

    def traverse(&handler)
      handler = method(:print_handler) unless handler.is_a?(Proc)

      root_pids.each { |pid| traverse_branch(pid, &handler) }
    end

    private

    def print_handler(process, level)
      indent = "  " * level
      prefix = level.zero? ? "" : "└─ "
      puts "#{indent}#{prefix}PID #{process.pid} (#{process.name})"
    end

    def build_process_map
      ProcTable.ps.each_with_object({}) do |process, map|
        map[process.pid] = { info: process, children: [] }
      end
    end

    def connect_children
      @process_map.each_value do |entry|
        parent_pid = entry[:info].ppid
        @process_map[parent_pid][:children] << entry[:info].pid if parent_pid && @process_map.key?(parent_pid)
      end
    end

    def root_pids
      return [@root_pid] if @root_pid

      @process_map.values
                  .select { |entry| entry[:info].ppid.nil? || !@process_map.key?(entry[:info].ppid) }
                  .map { |entry| entry[:info].pid }
    end

    def traverse_branch(pid, level = 0, &handler)
      return unless @process_map[pid]

      process = @process_map[pid][:info]

      handler.call(process, level)

      @process_map[pid][:children].each do |child_pid|
        traverse_branch(child_pid, level + 1, &handler)
      end
    end
  end
end
