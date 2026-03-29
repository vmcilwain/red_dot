# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RedDot::ResultPaths do
  describe '.normalize_failure_locations' do
    it 'returns locations when component_root is nil' do
      expect(described_class.normalize_failure_locations(['spec/x_spec.rb:1'], nil)).to eq(['spec/x_spec.rb:1'])
    end

    it 'prepends component_root when set' do
      expect(described_class.normalize_failure_locations(['spec/x_spec.rb:1'], 'components/a')).to eq(
        ['components/a/spec/x_spec.rb:1']
      )
    end

    it 'leaves paths unchanged when component_root is empty string' do
      expect(described_class.normalize_failure_locations(['spec/x_spec.rb:1'], '')).to eq(['spec/x_spec.rb:1'])
    end

    it 'prepends component_root for path-only locations' do
      expect(described_class.normalize_failure_locations(['spec/x_spec.rb'], 'components/a')).to eq(
        ['components/a/spec/x_spec.rb']
      )
    end
  end

  describe '.display_path_for_result_file' do
    it 'returns path when component_root is nil' do
      expect(described_class.display_path_for_result_file('spec/foo_spec.rb', nil)).to eq('spec/foo_spec.rb')
    end

    it 'prepends component_root when set' do
      expect(described_class.display_path_for_result_file('spec/foo_spec.rb', 'components/a')).to eq(
        'components/a/spec/foo_spec.rb'
      )
    end

    it 'returns path unchanged when component_root is empty string' do
      expect(described_class.display_path_for_result_file('spec/foo_spec.rb', '')).to eq('spec/foo_spec.rb')
    end
  end
end
