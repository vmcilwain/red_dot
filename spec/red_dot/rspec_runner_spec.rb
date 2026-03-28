# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe RedDot::RspecRunner do
  let(:working_dir) { Dir.mktmpdir('red_dot_runner') }

  after { FileUtils.rm_rf(working_dir) }

  describe '.build_argv' do
    it 'includes paths, json format and out path' do
      argv = described_class.build_argv(
        paths: ['spec/foo_spec.rb'],
        json_path: '/tmp/out.json',
        format: 'progress'
      )
      expect(argv).to include('spec/foo_spec.rb', '--format', 'json', '--out', '/tmp/out.json', '--format', 'progress')
    end

    it 'adds tags when given' do
      argv = described_class.build_argv(
        paths: ['spec/foo_spec.rb'],
        json_path: '/t.json',
        tags: %w[foo bar]
      )
      expect(argv).to include('--tag', 'foo', '--tag', 'bar')
    end

    it 'adds out_path when non-empty' do
      argv = described_class.build_argv(
        paths: ['spec/foo_spec.rb'],
        json_path: '/t.json',
        out_path: '/tmp/rspec.out'
      )
      expect(argv).to include('--out', '/tmp/rspec.out')
    end

    it 'adds --example when example_filter present' do
      argv = described_class.build_argv(
        paths: ['spec/foo_spec.rb'],
        json_path: '/t.json',
        example_filter: 'foo bar'
      )
      expect(argv).to include('--example', 'foo bar')
    end

    it 'adds --fail-fast when fail_fast true' do
      argv = described_class.build_argv(
        paths: ['spec/foo_spec.rb'],
        json_path: '/t.json',
        fail_fast: true
      )
      expect(argv).to include('--fail-fast')
    end

    it 'adds --seed when numeric' do
      argv = described_class.build_argv(
        paths: ['spec/foo_spec.rb'],
        json_path: '/t.json',
        seed: '12345'
      )
      expect(argv).to include('--seed', '12345')
    end

    it 'does not add --seed when not numeric' do
      argv = described_class.build_argv(
        paths: ['spec/foo_spec.rb'],
        json_path: '/t.json',
        seed: 'abc'
      )
      expect(argv).not_to include('--seed')
    end
  end

  describe '.rspec_command' do
    it 'returns bundle exec rspec when Gemfile present' do
      File.write(File.join(working_dir, 'Gemfile'), '')
      expect(described_class.rspec_command(working_dir)).to eq(%w[bundle exec rspec])
    end

    it 'returns rspec when no Gemfile' do
      expect(described_class.rspec_command(working_dir)).to eq(['rspec'])
    end
  end

  describe '.spawn' do
    it 'returns hash with :pid, :stdout_io, :json_path' do
      skip 'spawn starts real process' unless ENV['RED_DOT_INTEGRATION']

      File.write(File.join(working_dir, 'Gemfile'), "gem 'rspec'\n")
      FileUtils.mkdir_p(File.join(working_dir, 'spec'))
      File.write(File.join(working_dir, 'spec', 'foo_spec.rb'), "RSpec.describe 'x' do it { expect(1).to eq(1) } end\n")

      result = described_class.spawn(working_dir: working_dir, paths: ['spec/foo_spec.rb'])
      expect(result).to have_key(:pid)
      expect(result).to have_key(:stdout_io)
      expect(result).to have_key(:json_path)
      Process.wait(result[:pid]) if result[:pid]
    end
  end
end
