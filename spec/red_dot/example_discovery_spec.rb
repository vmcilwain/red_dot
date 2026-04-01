# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe RedDot::ExampleDiscovery do
  let(:working_dir) { Dir.mktmpdir('red_dot_examples') }
  let(:cache_path) { described_class.cache_file_path(working_dir) }

  after { FileUtils.rm_rf(working_dir) }

  describe '.cache_dir' do
    it 'defaults to ~/.cache/red_dot' do
      path = described_class.cache_dir
      expect(path).to end_with('red_dot')
      expect(path).to include('.cache')
    end

    it 'respects XDG_CACHE_HOME' do
      allow(ENV).to receive(:fetch).with('XDG_CACHE_HOME', anything).and_return('/custom/cache')
      expect(described_class.cache_dir).to eq('/custom/cache/red_dot')
    end
  end

  describe '.cache_file_path' do
    it 'returns path under cache_dir with hash of working_dir' do
      path = described_class.cache_file_path(working_dir)
      expect(path).to start_with(described_class.cache_dir)
      expect(path).to include('cache_')
      expect(path).to end_with('.json')
    end

    it 'is stable for same working_dir' do
      expect(described_class.cache_file_path(working_dir)).to eq(described_class.cache_file_path(working_dir))
    end
  end

  describe '.read_cache_file' do
    it 'returns empty hash when file missing' do
      expect(described_class.read_cache_file(working_dir)).to eq({})
    end

    it 'returns entries when valid JSON' do
      FileUtils.mkdir_p(File.dirname(cache_path))
      File.write(cache_path, '{"entries":{"spec/foo_spec.rb":{"sha256":"abc","examples":[]}}}')
      expect(described_class.read_cache_file(working_dir)).to have_key('spec/foo_spec.rb')
    end
  end

  describe '.get_cached_examples' do
    let(:spec_file) { File.join(working_dir, 'spec', 'foo_spec.rb') }

    before do
      FileUtils.mkdir_p(File.dirname(spec_file))
      File.write(spec_file, 'content')
    end

    it 'returns nil when no cache entry' do
      expect(described_class.get_cached_examples(working_dir, 'spec/foo_spec.rb')).to be_nil
    end

    it 'returns nil when sha256 mismatch' do
      FileUtils.mkdir_p(File.dirname(cache_path))
      File.write(cache_path, <<~JSON)
        {"entries":{"spec/foo_spec.rb":{"sha256":"wrong_hash","examples":[{"path":"spec/foo_spec.rb","line_number":1,"full_description":"x"}]}}}
      JSON
      expect(described_class.get_cached_examples(working_dir, 'spec/foo_spec.rb')).to be_nil
    end

    it 'returns ExampleInfo array when cache hit and sha256 match' do
      sha = described_class.file_sha256(spec_file)
      FileUtils.mkdir_p(File.dirname(cache_path))
      File.write(cache_path, <<~JSON)
        {"entries":{"spec/foo_spec.rb":{"sha256":"#{sha}","examples":[{"path":"spec/foo_spec.rb","line_number":1,"full_description":"Foo"}]}}}
      JSON
      examples = described_class.get_cached_examples(working_dir, 'spec/foo_spec.rb')
      expect(examples).not_to be_nil
      expect(examples.size).to eq(1)
      expect(examples.first).to have_attributes(path: 'spec/foo_spec.rb', line_number: 1, full_description: 'Foo')
    end
  end

  describe '.write_cached_examples' do
    let(:spec_file) { File.join(working_dir, 'spec', 'foo_spec.rb') }
    let(:examples) do
      [described_class::ExampleInfo.new(path: 'spec/foo_spec.rb', line_number: 10, full_description: 'Foo bar')]
    end

    before do
      FileUtils.mkdir_p(File.dirname(spec_file))
      File.write(spec_file, 'content')
    end

    it 'writes cache file and get_cached_examples returns examples' do
      described_class.write_cached_examples(working_dir, 'spec/foo_spec.rb', examples)
      result = described_class.get_cached_examples(working_dir, 'spec/foo_spec.rb')
      expect(result).not_to be_nil
      expect(result.first.full_description).to eq('Foo bar')
    end

    it 'stores sha256 instead of mtime' do
      described_class.write_cached_examples(working_dir, 'spec/foo_spec.rb', examples)
      entries = described_class.read_cache_file(working_dir)
      expect(entries['spec/foo_spec.rb']).to have_key('sha256')
      expect(entries['spec/foo_spec.rb']).not_to have_key('mtime')
    end
  end

  describe '.write_cached_examples_batch' do
    let(:spec_a) { File.join(working_dir, 'spec', 'a_spec.rb') }
    let(:spec_b) { File.join(working_dir, 'spec', 'b_spec.rb') }

    before do
      FileUtils.mkdir_p(File.join(working_dir, 'spec'))
      File.write(spec_a, 'a content')
      File.write(spec_b, 'b content')
    end

    it 'writes multiple paths in one pass' do
      results = {
        'spec/a_spec.rb' => [described_class::ExampleInfo.new(path: 'spec/a_spec.rb', line_number: 1, full_description: 'A')],
        'spec/b_spec.rb' => [described_class::ExampleInfo.new(path: 'spec/b_spec.rb', line_number: 2, full_description: 'B')]
      }
      described_class.write_cached_examples_batch(working_dir, results)
      expect(described_class.get_cached_examples(working_dir, 'spec/a_spec.rb')).not_to be_nil
      expect(described_class.get_cached_examples(working_dir, 'spec/b_spec.rb')).not_to be_nil
    end
  end

  describe '.stale_paths' do
    let(:discovery) { RedDot::SpecDiscovery.new(working_dir: working_dir) }

    before do
      FileUtils.mkdir_p(File.join(working_dir, 'spec'))
      File.write(File.join(working_dir, 'spec', 'a_spec.rb'), 'a')
      File.write(File.join(working_dir, 'spec', 'b_spec.rb'), 'b')
    end

    it 'returns all paths when cache is missing' do
      result = described_class.stale_paths(discovery)
      expect(result.size).to eq(2)
    end

    it 'returns empty when all paths are fresh' do
      described_class.write_cached_examples(working_dir, 'spec/a_spec.rb', [])
      described_class.write_cached_examples(working_dir, 'spec/b_spec.rb', [])
      expect(described_class.stale_paths(discovery)).to be_empty
    end

    it 'returns only stale paths' do
      described_class.write_cached_examples(working_dir, 'spec/a_spec.rb', [])
      result = described_class.stale_paths(discovery)
      expect(result.size).to eq(1)
      expect(result.first).to include('b_spec.rb')
    end
  end

  describe '.index_stale_count' do
    let(:discovery) { RedDot::SpecDiscovery.new(working_dir: working_dir) }

    before do
      FileUtils.mkdir_p(File.join(working_dir, 'spec'))
      File.write(File.join(working_dir, 'spec', 'a_spec.rb'), 'a')
      File.write(File.join(working_dir, 'spec', 'b_spec.rb'), 'b')
    end

    it 'returns 0 when there are no spec files' do
      empty = Dir.mktmpdir('red_dot_empty_specs')
      expect(described_class.index_stale_count(RedDot::SpecDiscovery.new(working_dir: empty))).to eq(0)
    ensure
      FileUtils.rm_rf(empty)
    end

    it 'counts all paths when cache is missing' do
      expect(described_class.index_stale_count(discovery)).to eq(2)
    end

    it 'returns 0 when every path has a fresh cache entry' do
      described_class.write_cached_examples(working_dir, 'spec/a_spec.rb', [])
      described_class.write_cached_examples(working_dir, 'spec/b_spec.rb', [])
      expect(described_class.index_stale_count(discovery)).to eq(0)
    end

    it 'counts a path when sha256 does not match cache' do
      described_class.write_cached_examples(working_dir, 'spec/a_spec.rb', [])
      described_class.write_cached_examples(working_dir, 'spec/b_spec.rb', [])
      File.write(File.join(working_dir, 'spec', 'a_spec.rb'), 'changed content')
      expect(described_class.index_stale_count(discovery)).to eq(1)
    end
  end

  describe '.index_fully_cold?' do
    let(:discovery) { RedDot::SpecDiscovery.new(working_dir: working_dir) }

    before do
      FileUtils.mkdir_p(File.join(working_dir, 'spec'))
      File.write(File.join(working_dir, 'spec', 'only_spec.rb'), 'content')
    end

    it 'is true when every spec is stale' do
      expect(described_class.index_fully_cold?(discovery)).to be true
    end

    it 'is false when cache is fresh for all specs' do
      described_class.write_cached_examples(working_dir, 'spec/only_spec.rb', [])
      expect(described_class.index_fully_cold?(discovery)).to be false
    end

    it 'is false when the tree is empty' do
      empty = Dir.mktmpdir('red_dot_no_specs')
      expect(described_class.index_fully_cold?(RedDot::SpecDiscovery.new(working_dir: empty))).to be false
    ensure
      FileUtils.rm_rf(empty)
    end
  end

  describe '.discover' do
    it 'calls RspecRunner.run_dry_run and parses JSON', :aggregate_failures do
      allow(RedDot::RspecRunner).to receive(:run_dry_run) do |**_opts|
        Tempfile.new(['list', '.json']).tap do |f|
          f.write('{"examples":[{"file_path":"spec/foo_spec.rb","line_number":5,"full_description":"Foo"}]}')
          f.close
        end.path
      end

      FileUtils.mkdir_p(File.join(working_dir, 'spec'))
      File.write(File.join(working_dir, 'spec', 'foo_spec.rb'), 'content')

      result = described_class.discover(working_dir: working_dir, path: 'spec/foo_spec.rb')
      expect(result).to be_an(Array)
      expect(result.first).to have_attributes(path: 'spec/foo_spec.rb', line_number: 5, full_description: 'Foo')
    end

    it 'writes cache with empty examples when dry-run JSON is empty so index is not stuck stale' do
      allow(RedDot::RspecRunner).to receive(:run_dry_run) do |**_opts|
        Tempfile.new(['empty', '.json']).tap do |f|
          f.write('')
          f.close
        end.path
      end

      FileUtils.mkdir_p(File.join(working_dir, 'spec'))
      File.write(File.join(working_dir, 'spec', 'empty_spec.rb'), 'RSpec.describe(:x) { }')

      described_class.discover(working_dir: working_dir, path: 'spec/empty_spec.rb')
      expect(described_class.get_cached_examples(working_dir, 'spec/empty_spec.rb')).not_to be_nil
      expect(described_class.index_stale_count(RedDot::SpecDiscovery.new(working_dir: working_dir))).to eq(0)
    end
  end

  describe '.discover_batch' do
    it 'calls RspecRunner.run_dry_run_batch and partitions by file' do
      allow(RedDot::RspecRunner).to receive(:run_dry_run_batch) do |**_opts|
        Tempfile.new(['batch', '.json']).tap do |f|
          data = {
            'examples' => [
              { 'file_path' => './spec/a_spec.rb', 'line_number' => 1, 'full_description' => 'A test' },
              { 'file_path' => './spec/b_spec.rb', 'line_number' => 2, 'full_description' => 'B test' },
              { 'file_path' => './spec/a_spec.rb', 'line_number' => 3, 'full_description' => 'A2 test' }
            ]
          }
          f.write(JSON.generate(data))
          f.close
        end.path
      end

      FileUtils.mkdir_p(File.join(working_dir, 'spec'))
      File.write(File.join(working_dir, 'spec', 'a_spec.rb'), 'a')
      File.write(File.join(working_dir, 'spec', 'b_spec.rb'), 'b')

      results = described_class.discover_batch(working_dir: working_dir, paths: %w[spec/a_spec.rb spec/b_spec.rb])
      expect(results.keys).to contain_exactly('spec/a_spec.rb', 'spec/b_spec.rb')
      expect(results['spec/a_spec.rb'].size).to eq(2)
      expect(results['spec/b_spec.rb'].size).to eq(1)
    end

    it 'caches all results from a batch' do
      allow(RedDot::RspecRunner).to receive(:run_dry_run_batch) do |**_opts|
        Tempfile.new(['batch', '.json']).tap do |f|
          data = {
            'examples' => [
              { 'file_path' => './spec/c_spec.rb', 'line_number' => 1, 'full_description' => 'C' }
            ]
          }
          f.write(JSON.generate(data))
          f.close
        end.path
      end

      FileUtils.mkdir_p(File.join(working_dir, 'spec'))
      File.write(File.join(working_dir, 'spec', 'c_spec.rb'), 'c')

      described_class.discover_batch(working_dir: working_dir, paths: ['spec/c_spec.rb'])
      expect(described_class.get_cached_examples(working_dir, 'spec/c_spec.rb')).not_to be_nil
    end
  end

  describe '.purge_cached_path' do
    let(:spec_file) { File.join(working_dir, 'spec', 'to_remove_spec.rb') }

    before do
      FileUtils.mkdir_p(File.dirname(spec_file))
      File.write(spec_file, 'content')
      described_class.write_cached_examples(working_dir, 'spec/to_remove_spec.rb', [])
    end

    it 'removes the path from cache' do
      described_class.purge_cached_path(working_dir, 'spec/to_remove_spec.rb')
      entries = described_class.read_cache_file(working_dir)
      expect(entries).not_to have_key('spec/to_remove_spec.rb')
    end

    it 'is a no-op for paths not in cache' do
      expect { described_class.purge_cached_path(working_dir, 'spec/nonexistent_spec.rb') }.not_to raise_error
    end
  end
end
