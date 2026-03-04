# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'tmpdir'

module RedDot
  class ExampleDiscovery
    ExampleInfo = Struct.new(:path, :line_number, :full_description, keyword_init: true)

    CACHE_DIR = File.join(Dir.tmpdir, 'red_dot').freeze

    def self.cache_file_path(working_dir)
      hash = Digest::SHA256.hexdigest(File.expand_path(working_dir))[0, 16]
      File.join(CACHE_DIR, "cache_#{hash}.json")
    end

    def self.read_cache_file(working_dir)
      path = cache_file_path(working_dir)
      return {} unless File.readable?(path)

      raw = File.read(path)
      return {} if raw.strip.empty?

      data = JSON.parse(raw)
      data['entries'] || {}
    rescue JSON::ParserError, Errno::ENOENT
      {}
    end

    def self.get_cached_examples(working_dir, path)
      full_path = File.join(working_dir, path)
      return nil unless File.exist?(full_path)

      entries = read_cache_file(working_dir)
      entry = entries[path]
      return nil unless entry

      current_mtime = File.mtime(full_path).to_f
      return nil unless current_mtime == entry['mtime']

      (entry['examples'] || []).map do |ex|
        ExampleInfo.new(
          path: ex['path'],
          line_number: ex['line_number'],
          full_description: ex['full_description'].to_s
        )
      end
    end

    def self.write_cached_examples(working_dir, path, examples)
      full_path = File.join(working_dir, path)
      mtime = File.exist?(full_path) ? File.mtime(full_path).to_f : 0
      entries = read_cache_file(working_dir)
      entries[path] = {
        'mtime' => mtime,
        'examples' => examples.map do |e|
          { 'path' => e.path, 'line_number' => e.line_number, 'full_description' => e.full_description }
        end
      }
      FileUtils.mkdir_p(CACHE_DIR)
      File.write(cache_file_path(working_dir), JSON.generate({ 'entries' => entries }))
    end

    def self.discover(working_dir:, path:)
      json_path = RspecRunner.run_dry_run(working_dir: working_dir, paths: [path])
      return [] unless json_path && File.readable?(json_path)

      raw = File.read(json_path)
      return [] if raw.strip.empty?

      data = JSON.parse(raw)
      examples = (data['examples'] || []).map do |ex|
        ExampleInfo.new(
          path: ex['file_path'],
          line_number: ex['line_number'],
          full_description: ex['full_description'].to_s
        )
      end
      write_cached_examples(working_dir, path, examples)
      examples
    rescue JSON::ParserError, Errno::ENOENT
      []
    end
  end
end
