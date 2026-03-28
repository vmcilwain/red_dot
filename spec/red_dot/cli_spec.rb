# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RedDot::Cli do
  describe '.parse' do
    it 'returns working_dir and option_overrides' do
      result = described_class.parse([])
      expect(result).to have_key(:working_dir)
      expect(result).to have_key(:option_overrides)
      expect(result[:option_overrides]).to eq({})
    end

    it 'uses Dir.pwd when no dir arg' do
      expect(described_class.parse([])[:working_dir]).to eq(Dir.pwd)
    end

    it 'uses first non-option as working_dir' do
      result = described_class.parse(['/path/to/project'])
      expect(result[:working_dir]).to eq('/path/to/project')
    end

    it 'parses --format' do
      result = described_class.parse(%w[--format documentation])
      expect(result[:option_overrides][:format]).to eq('documentation')
    end

    it 'parses --tag (single)' do
      result = described_class.parse(%w[--tag foo])
      expect(result[:option_overrides][:tags]).to eq(['foo'])
    end

    it 'parses multiple --tag' do
      result = described_class.parse(%w[--tag foo --tag bar])
      expect(result[:option_overrides][:tags]).to eq(%w[foo bar])
    end

    it 'parses --out' do
      result = described_class.parse(%w[--out /tmp/out.txt])
      expect(result[:option_overrides][:out_path]).to eq('/tmp/out.txt')
    end

    it 'parses --example' do
      result = described_class.parse(['--example', 'foo bar'])
      expect(result[:option_overrides][:example_filter]).to eq('foo bar')
    end

    it 'parses --line' do
      result = described_class.parse(%w[--line 42])
      expect(result[:option_overrides][:line_number]).to eq('42')
    end

    it 'parses --fail-fast' do
      result = described_class.parse(%w[--fail-fast])
      expect(result[:option_overrides][:fail_fast]).to be true
    end

    it 'parses --full-output' do
      result = described_class.parse(%w[--full-output])
      expect(result[:option_overrides][:full_output]).to be true
    end
  end
end
