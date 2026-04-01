# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'tempfile'

module RedDot
  # Discovers and caches example names (e.g. for find). ExampleInfo: path, line_number, full_description.
  class ExampleDiscovery
    ExampleInfo = Struct.new(:path, :line_number, :full_description, keyword_init: true)

    def self.cache_dir
      base = ENV.fetch('XDG_CACHE_HOME', File.join(Dir.home, '.cache'))
      File.join(base, 'red_dot')
    end

    # @return [String] path to JSON cache for working_dir
    def self.cache_file_path(working_dir)
      hash = Digest::SHA256.hexdigest(File.expand_path(working_dir))[0, 16]
      File.join(cache_dir, "cache_#{hash}.json")
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

    # @return [Integer] number of discovered spec paths with stale or missing cache
    def self.index_stale_count(spec_discovery, paths = nil)
      paths = spec_discovery.discover if paths.nil?
      return 0 if paths.empty?

      paths.count do |display_path|
        ctx = spec_discovery.run_context_for(display_path)
        get_cached_examples(ctx[:run_cwd], ctx[:rspec_path]).nil?
      end
    end

    # True when every discovered spec has a stale cache.
    def self.index_fully_cold?(spec_discovery)
      paths = spec_discovery.discover
      paths.any? && index_stale_count(spec_discovery, paths) == paths.size
    end

    # @return [Array<String>] display paths whose cache is missing or stale
    def self.stale_paths(spec_discovery, paths = nil)
      paths = spec_discovery.discover if paths.nil?
      return [] if paths.empty?

      paths.select do |display_path|
        ctx = spec_discovery.run_context_for(display_path)
        get_cached_examples(ctx[:run_cwd], ctx[:rspec_path]).nil?
      end
    end

    # @return [String] SHA256 hex digest of file contents
    def self.file_sha256(full_path)
      Digest::SHA256.file(full_path).hexdigest
    end

    # @return [Array<ExampleInfo>, nil] cached examples if SHA256 matches, else nil
    def self.get_cached_examples(working_dir, path)
      full_path = File.join(working_dir, path)
      return nil unless File.exist?(full_path)

      entries = read_cache_file(working_dir)
      entry = entries[path]
      return nil unless entry

      return nil unless entry['sha256'] == file_sha256(full_path)

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
      sha = File.exist?(full_path) ? file_sha256(full_path) : ''
      entries = read_cache_file(working_dir)
      entries[path] = {
        'sha256' => sha,
        'examples' => examples.map do |e|
          { 'path' => e.path, 'line_number' => e.line_number, 'full_description' => e.full_description }
        end
      }
      write_cache_file_atomic(working_dir, entries)
    end

    # Batch-write multiple paths into the cache in one pass.
    def self.write_cached_examples_batch(working_dir, results_by_path)
      entries = read_cache_file(working_dir)
      results_by_path.each do |path, examples|
        full_path = File.join(working_dir, path)
        sha = File.exist?(full_path) ? file_sha256(full_path) : ''
        entries[path] = {
          'sha256' => sha,
          'examples' => examples.map do |e|
            { 'path' => e.path, 'line_number' => e.line_number, 'full_description' => e.full_description }
          end
        }
      end
      write_cache_file_atomic(working_dir, entries)
    end

    # Runs rspec --dry-run, parses JSON, caches and returns ExampleInfo list.
    def self.discover(working_dir:, path:)
      full_path = File.join(working_dir, path)
      return [] unless File.exist?(full_path)

      json_path = RspecRunner.run_dry_run(working_dir: working_dir, paths: [path])
      examples = examples_from_dry_run_json(json_path)
      write_cached_examples(working_dir, path, examples)
      examples
    end

    # Batch discover: single rspec --dry-run for all paths, partition results by file.
    # @return [Hash{String => Array<ExampleInfo>}] keyed by spec path
    def self.discover_batch(working_dir:, paths:)
      existing = paths.select { |p| File.exist?(File.join(working_dir, p)) }
      return {} if existing.empty?

      json_path = RspecRunner.run_dry_run_batch(working_dir: working_dir, paths: existing)
      all_examples = examples_from_dry_run_json(json_path)

      results = existing.to_h { |p| [p, []] }
      all_examples.each do |ex|
        normalized = ex.path.sub(%r{\A\./}, '')
        results[normalized] = [] unless results.key?(normalized)
        results[normalized] << ex
      end

      write_cached_examples_batch(working_dir, results)
      results
    end

    # Remove a path from the cache (e.g. when file is deleted).
    def self.purge_cached_path(working_dir, path)
      entries = read_cache_file(working_dir)
      return unless entries.key?(path)

      entries.delete(path)
      write_cache_file_atomic(working_dir, entries)
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

    # Atomic write: tempfile + rename prevents corrupt reads on crash.
    def self.write_cache_file_atomic(working_dir, entries)
      dir = cache_dir
      FileUtils.mkdir_p(dir)
      target = cache_file_path(working_dir)
      tmp = Tempfile.new('red_dot_cache', dir)
      tmp.write(JSON.generate({ 'entries' => entries }))
      tmp.close
      File.rename(tmp.path, target)
    rescue StandardError
      tmp&.close
      tmp&.unlink
    end
    private_class_method :write_cache_file_atomic
  end
end
