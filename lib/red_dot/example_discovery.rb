# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'tmpdir'

module RedDot
  # Discovers and caches example names (e.g. for find). ExampleInfo: path, line_number, full_description.
  class ExampleDiscovery
    ExampleInfo = Struct.new(:path, :line_number, :full_description, keyword_init: true)

    CACHE_DIR = File.join(Dir.tmpdir, 'red_dot').freeze

    # @return [String] path to JSON cache for working_dir
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

    # @return [Integer] number of discovered spec paths with no cache entry or stale mtime
    # @param spec_discovery [SpecDiscovery]
    # @param paths [Array<String>, nil] if nil, calls spec_discovery.discover
    def self.index_stale_count(spec_discovery, paths = nil)
      paths = spec_discovery.discover if paths.nil?
      return 0 if paths.empty?

      paths.count do |display_path|
        ctx = spec_discovery.run_context_for(display_path)
        get_cached_examples(ctx[:run_cwd], ctx[:rspec_path]).nil?
      end
    end

    # True when every discovered spec has a stale cache (same as "never indexed" for a non-empty tree).
    def self.index_fully_cold?(spec_discovery)
      paths = spec_discovery.discover
      paths.any? && index_stale_count(spec_discovery, paths) == paths.size
    end

    # @return [Array<ExampleInfo>, nil] cached examples if mtime matches, else nil
    def self.get_cached_examples(working_dir, path)
      full_path = File.join(working_dir, path)
      return nil unless File.exist?(full_path)

      entries = read_cache_file(working_dir)
      entry = entries[path]
      return nil unless entry

      cached_mtime = entry['mtime'].to_f
      current_mtime = File.mtime(full_path).to_f
      return nil unless (current_mtime - cached_mtime).abs < 1e-6

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

    # Runs rspec --dry-run, parses JSON, caches and returns ExampleInfo list.
    # Always writes the cache when the spec file exists so index staleness clears even when
    # dry-run yields no/invalid JSON (rspec failure, empty output, etc.).
    def self.discover(working_dir:, path:)
      full_path = File.join(working_dir, path)
      return [] unless File.exist?(full_path)

      json_path = RspecRunner.run_dry_run(working_dir: working_dir, paths: [path])
      examples = examples_from_dry_run_json(json_path)
      write_cached_examples(working_dir, path, examples)
      examples
    end

    def self.examples_from_dry_run_json(json_path)
      return [] unless json_path && File.readable?(json_path)

      raw = File.read(json_path)
      return [] if raw.strip.empty?

      data = JSON.parse(raw)
      (data['examples'] || []).map do |ex|
        ExampleInfo.new(
          path: ex['file_path'],
          line_number: ex['line_number'],
          full_description: ex['full_description'].to_s
        )
      end
    rescue JSON::ParserError, Errno::ENOENT
      []
    end
    private_class_method :examples_from_dry_run_json
  end
end
