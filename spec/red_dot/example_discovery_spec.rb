# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe RedDot::ExampleDiscovery do
  let(:working_dir) { Dir.mktmpdir('red_dot_examples') }
  let(:cache_path) { described_class.cache_file_path(working_dir) }

  after { FileUtils.rm_rf(working_dir) }

  describe '.cache_file_path' do
    it 'returns path under CACHE_DIR with hash of working_dir' do
      path = described_class.cache_file_path(working_dir)
      expect(path).to start_with(described_class::CACHE_DIR)
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
      File.write(cache_path, '{"entries":{"spec/foo_spec.rb":{"mtime":0,"examples":[]}}}')
      expect(described_class.read_cache_file(working_dir)).to have_key('spec/foo_spec.rb')
    end
  end

  describe '.get_cached_examples' do
    let(:spec_file) { File.join(working_dir, 'spec', 'foo_spec.rb') }

    before do
      FileUtils.mkdir_p(File.dirname(spec_file))
      File.write(spec_file, '')
    end

    it 'returns nil when no cache entry' do
      expect(described_class.get_cached_examples(working_dir, 'spec/foo_spec.rb')).to be_nil
    end

    it 'returns nil when mtime mismatch' do
      FileUtils.mkdir_p(File.dirname(cache_path))
      File.write(cache_path, <<~JSON)
        {"entries":{"spec/foo_spec.rb":{"mtime":0,"examples":[{"path":"spec/foo_spec.rb","line_number":1,"full_description":"x"}]}}}
      JSON
      expect(described_class.get_cached_examples(working_dir, 'spec/foo_spec.rb')).to be_nil
    end

    it 'returns ExampleInfo array when cache hit and mtime match' do
      mtime = File.mtime(spec_file).to_f
      FileUtils.mkdir_p(File.dirname(cache_path))
      File.write(cache_path, <<~JSON)
        {"entries":{"spec/foo_spec.rb":{"mtime":#{mtime},"examples":[{"path":"spec/foo_spec.rb","line_number":1,"full_description":"Foo"}]}}}
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
      File.write(spec_file, '')
    end

    it 'writes cache file and get_cached_examples returns examples' do
      described_class.write_cached_examples(working_dir, 'spec/foo_spec.rb', examples)
      expect(described_class.get_cached_examples(working_dir, 'spec/foo_spec.rb')).not_to be_nil
      expect(described_class.get_cached_examples(working_dir, 'spec/foo_spec.rb').first.full_description).to eq('Foo bar')
    end
  end

  describe '.index_stale_count' do
    let(:discovery) { RedDot::SpecDiscovery.new(working_dir: working_dir) }

    before do
      FileUtils.mkdir_p(File.join(working_dir, 'spec'))
      File.write(File.join(working_dir, 'spec', 'a_spec.rb'), '')
      File.write(File.join(working_dir, 'spec', 'b_spec.rb'), '')
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
      mtime_a = File.mtime(File.join(working_dir, 'spec', 'a_spec.rb')).to_f
      mtime_b = File.mtime(File.join(working_dir, 'spec', 'b_spec.rb')).to_f
      FileUtils.mkdir_p(File.dirname(cache_path))
      File.write(
        cache_path,
        JSON.generate(
          'entries' => {
            'spec/a_spec.rb' => { 'mtime' => mtime_a, 'examples' => [] },
            'spec/b_spec.rb' => { 'mtime' => mtime_b, 'examples' => [] }
          }
        )
      )
      expect(described_class.index_stale_count(discovery)).to eq(0)
    end

    it 'counts a path when mtime does not match cache' do
      mtime_b = File.mtime(File.join(working_dir, 'spec', 'b_spec.rb')).to_f
      FileUtils.mkdir_p(File.dirname(cache_path))
      File.write(
        cache_path,
        JSON.generate(
          'entries' => {
            'spec/a_spec.rb' => { 'mtime' => 0, 'examples' => [] },
            'spec/b_spec.rb' => { 'mtime' => mtime_b, 'examples' => [] }
          }
        )
      )
      expect(described_class.index_stale_count(discovery)).to eq(1)
    end

    it 'accepts a precomputed paths list to avoid duplicate discovery' do
      paths = discovery.discover
      expect(described_class.index_stale_count(discovery, paths)).to eq(2)
    end
  end

  describe '.index_fully_cold?' do
    let(:discovery) { RedDot::SpecDiscovery.new(working_dir: working_dir) }

    before do
      FileUtils.mkdir_p(File.join(working_dir, 'spec'))
      File.write(File.join(working_dir, 'spec', 'only_spec.rb'), '')
    end

    it 'is true when every spec is stale' do
      expect(described_class.index_fully_cold?(discovery)).to be true
    end

    it 'is false when cache is fresh for all specs' do
      mtime = File.mtime(File.join(working_dir, 'spec', 'only_spec.rb')).to_f
      FileUtils.mkdir_p(File.dirname(cache_path))
      File.write(
        cache_path,
        JSON.generate('entries' => { 'spec/only_spec.rb' => { 'mtime' => mtime, 'examples' => [] } })
      )
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
      json_path = nil
      allow(RedDot::RspecRunner).to receive(:run_dry_run) do |**_opts|
        json_path = Tempfile.new(['list', '.json']).tap do |f|
          f.write('{"examples":[{"file_path":"spec/foo_spec.rb","line_number":5,"full_description":"Foo"}]}')
          f.close
        end.path
        json_path
      end

      FileUtils.mkdir_p(File.join(working_dir, 'spec'))
      File.write(File.join(working_dir, 'spec', 'foo_spec.rb'), '')

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
end
