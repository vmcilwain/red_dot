# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe RedDot::SpecDiscovery do
  let(:working_dir) { Dir.mktmpdir('red_dot_spec_discovery') }
  let(:spec_dir) { File.join(working_dir, 'spec') }
  let(:discovery) { described_class.new(working_dir: working_dir) }

  after { FileUtils.rm_rf(working_dir) }

  shared_examples 'single-project discovery' do
    before { FileUtils.mkdir_p(spec_dir) }

    describe '#umbrella?' do
      it 'returns false when no components dir' do
        expect(discovery.umbrella?).to be false
      end
    end

    describe '#discover' do
      it 'returns empty when no spec files' do
        expect(discovery.discover).to eq([])
      end

      it 'returns relative paths to _spec.rb files sorted' do
        File.write(File.join(spec_dir, 'foo_spec.rb'), '')
        File.write(File.join(spec_dir, 'bar_spec.rb'), '')
        expect(discovery.discover).to eq(%w[spec/bar_spec.rb spec/foo_spec.rb])
      end
    end

    describe '#discover_grouped_by_dir' do
      it 'groups by directory with sorted files' do
        File.write(File.join(spec_dir, 'foo_spec.rb'), '')
        File.write(File.join(spec_dir, 'bar_spec.rb'), '')
        expect(discovery.discover_grouped_by_dir).to eq('spec' => %w[spec/bar_spec.rb spec/foo_spec.rb])
      end
    end

    describe '#run_context_for' do
      it 'returns working_dir and display_path as rspec_path' do
        ctx = discovery.run_context_for('spec/foo_spec.rb')
        expect(ctx).to eq(run_cwd: working_dir, rspec_path: 'spec/foo_spec.rb')
      end
    end

    describe '#default_run_all_paths' do
      it 'returns relative_spec_path when single project' do
        expect(discovery.default_run_all_paths).to eq(['spec'])
      end
    end
  end

  context 'standard spec/ directory' do
    include_examples 'single-project discovery'
  end

  context 'with .rspec default-path' do
    let(:custom_dir) { File.join(working_dir, 'tests') }

    before do
      FileUtils.mkdir_p(custom_dir)
      File.write(File.join(working_dir, '.rspec'), "--default-path tests\n")
      File.write(File.join(custom_dir, 'a_spec.rb'), '')
    end

    it 'discovers from default-path' do
      expect(discovery.discover).to eq(['tests/a_spec.rb'])
    end

    it 'default_run_all_paths uses default-path' do
      expect(discovery.default_run_all_paths).to eq(['tests'])
    end
  end

  context 'umbrella project' do
    let(:components_dir) { File.join(working_dir, 'components') }
    let(:comp_a_spec) { File.join(components_dir, 'a', 'spec') }
    let(:comp_b_spec) { File.join(components_dir, 'b', 'spec') }

    before do
      FileUtils.mkdir_p(comp_a_spec)
      FileUtils.mkdir_p(comp_b_spec)
    end

    describe '#umbrella?' do
      it 'returns true when components/ exists' do
        expect(discovery.umbrella?).to be true
      end
    end

    describe '#component_roots' do
      it 'returns sorted component paths with spec dir' do
        roots = discovery.component_roots
        expect(roots).to include('components/a', 'components/b')
        expect(roots).to eq(roots.sort)
      end
    end

    describe '#discover' do
      it 'returns relative paths from all components' do
        File.write(File.join(comp_a_spec, 'foo_spec.rb'), '')
        File.write(File.join(comp_b_spec, 'bar_spec.rb'), '')
        files = discovery.discover
        expect(files).to include('components/a/spec/foo_spec.rb', 'components/b/spec/bar_spec.rb')
      end
    end

    describe '#run_context_for' do
      it 'resolves run_cwd and rspec_path for component path' do
        File.write(File.join(comp_a_spec, 'foo_spec.rb'), '')
        ctx = discovery.run_context_for('components/a/spec/foo_spec.rb')
        expect(ctx[:run_cwd]).to eq(File.join(working_dir, 'components/a'))
        expect(ctx[:rspec_path]).to eq('spec/foo_spec.rb')
      end
    end
  end

  describe '#empty_state_message' do
    it 'mentions no spec files when spec dir exists but empty' do
      FileUtils.mkdir_p(spec_dir)
      expect(discovery.empty_state_message).to include('No spec files')
    end
  end
end
