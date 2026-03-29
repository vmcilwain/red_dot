# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'fileutils'

RSpec.describe RedDot::Config do
  let(:working_dir) { Dir.mktmpdir('red_dot_config') }
  let(:project_config_path) { File.join(working_dir, '.red_dot.yml') }

  after { FileUtils.rm_rf(working_dir) }

  describe 'VALID_EDITORS' do
    it 'includes vscode, cursor, textmate' do
      expect(described_class::VALID_EDITORS).to contain_exactly('vscode', 'cursor', 'textmate')
    end
  end

  describe '.parse_tags' do
    it 'splits on comma and whitespace' do
      expect(described_class.parse_tags('a, b  c')).to eq(%w[a b c])
    end

    it 'returns [] for blank string' do
      expect(described_class.parse_tags('  ')).to eq([])
    end

    it 'coerces non-String with #to_s before splitting' do
      expect(described_class.parse_tags(123)).to eq(%w[123])
    end
  end

  describe '.project_config_path' do
    it 'returns .red_dot.yml in expanded working_dir' do
      expect(described_class.project_config_path(working_dir)).to eq(File.expand_path(project_config_path))
    end
  end

  describe '.load' do
    it 'returns DEFAULT_OPTIONS when no config files exist' do
      result = described_class.load(working_dir: working_dir)
      expect(result).to include(
        tags: [],
        tags_str: '',
        format: 'progress',
        fail_fast: false,
        full_output: false,
        editor: 'cursor'
      )
    end

    context 'with project config' do
      before do
        File.write(project_config_path, <<~YAML)
          format: documentation
          fail_fast: true
          tags: [foo, bar]
          editor: vscode
        YAML
      end

      it 'merges project config over defaults' do
        result = described_class.load(working_dir: working_dir)
        expect(result[:format]).to eq('documentation')
        expect(result[:fail_fast]).to be true
        expect(result[:tags]).to eq(%w[foo bar])
        expect(result[:editor]).to eq('vscode')
      end

      it 'merges full_output' do
        File.write(project_config_path, "full_output: true\n")
        result = described_class.load(working_dir: working_dir)
        expect(result[:full_output]).to be true
      end
    end

    context 'with output key' do
      before { File.write(project_config_path, "output: /tmp/out.txt\n") }

      it 'maps output to out_path' do
        result = described_class.load(working_dir: working_dir)
        expect(result[:out_path]).to eq('/tmp/out.txt')
      end
    end
  end

  describe '.merge_file' do
    let(:opts) { described_class::DEFAULT_OPTIONS.dup }

    it 'returns opts when path is nil' do
      expect(described_class.merge_file(opts, nil)).to eq(opts)
    end

    it 'returns opts when path is not readable' do
      expect(described_class.merge_file(opts, '/nonexistent')).to eq(opts)
    end

    context 'with valid YAML file' do
      let(:path) { File.join(working_dir, 'config.yml') }

      before { File.write(path, "format: documentation\nfail_fast: true\n") }

      it 'merges file contents into opts' do
        result = described_class.merge_file(opts, path)
        expect(result[:format]).to eq('documentation')
        expect(result[:fail_fast]).to be true
      end
    end
  end

  describe '.merge_overrides!' do
    let(:opts) { described_class::DEFAULT_OPTIONS.dup }

    it 'returns opts unchanged when overrides are nil or empty' do
      expect(described_class.merge_overrides!(opts, nil)).to eq(opts)
      expect(described_class.merge_overrides!(opts, {})).to eq(opts)
    end

    it 'merges tags array and tags_str' do
      described_class.merge_overrides!(opts, tags: %w[a b])
      expect(opts[:tags]).to eq(%w[a b])
      expect(opts[:tags_str]).to eq('a, b')
    end

    it 'parses tags from tags_str when tags array is not given' do
      described_class.merge_overrides!(opts, tags_str: 'foo bar')
      expect(opts[:tags_str]).to eq('foo bar')
      expect(opts[:tags]).to eq(%w[foo bar])
    end

    it 'keeps tags from array when both tags and tags_str are given' do
      described_class.merge_overrides!(opts, tags: %w[a b], tags_str: 'c d')
      expect(opts[:tags]).to eq(%w[a b])
      expect(opts[:tags_str]).to eq('c d')
    end

    it 'sets editor only when valid' do
      described_class.merge_overrides!(opts, editor: 'vscode')
      expect(opts[:editor]).to eq('vscode')
      described_class.merge_overrides!(opts, editor: 'invalid')
      expect(opts[:editor]).to eq('vscode')
    end
  end

  describe '.array_or_parse' do
    it 'returns array when tags_val is Array' do
      expect(described_class.array_or_parse([], %w[a b], '')).to eq(%w[a b])
    end

    it 'parses tags_str when tags_val not Array and tags_str present' do
      expect(described_class.array_or_parse([], nil, 'x, y')).to eq(%w[x y])
    end

    it 'returns existing when neither tags_val nor tags_str usable' do
      expect(described_class.array_or_parse(%w[z], nil, '')).to eq(%w[z])
    end
  end

  describe '.component_roots' do
    it 'returns nil when no project config' do
      expect(described_class.component_roots(working_dir: working_dir)).to be_nil
    end

    it 'returns nil when config has no components key' do
      File.write(project_config_path, "format: progress\n")
      expect(described_class.component_roots(working_dir: working_dir)).to be_nil
    end

    it 'returns component roots array when present' do
      File.write(project_config_path, "components:\n  - components/a\n  - components/b\n")
      expect(described_class.component_roots(working_dir: working_dir)).to eq(%w[components/a components/b])
    end
  end
end
