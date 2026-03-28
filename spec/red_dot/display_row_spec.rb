# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RedDot::DisplayRow do
  let(:file_row) { described_class.new(type: :file, path: 'spec/foo_spec.rb', line_number: nil, full_description: nil) }
  let(:example_row) do
    described_class.new(type: :example, path: 'spec/foo_spec.rb', line_number: 42, full_description: 'Foo does bar')
  end

  describe '#file_row?' do
    it 'returns true for type :file' do
      expect(file_row.file_row?).to be true
    end

    it 'returns false for type :example' do
      expect(example_row.file_row?).to be false
    end
  end

  describe '#example_row?' do
    it 'returns true for type :example' do
      expect(example_row.example_row?).to be true
    end

    it 'returns false for type :file' do
      expect(file_row.example_row?).to be false
    end
  end

  describe '#runnable_path' do
    it 'returns path for file row' do
      expect(file_row.runnable_path).to eq('spec/foo_spec.rb')
    end

    it 'returns path:line for example row' do
      expect(example_row.runnable_path).to eq('spec/foo_spec.rb:42')
    end
  end

  describe '#row_id' do
    it 'returns path for file row' do
      expect(file_row.row_id).to eq('spec/foo_spec.rb')
    end

    it 'returns path:line for example row' do
      expect(example_row.row_id).to eq('spec/foo_spec.rb:42')
    end
  end
end
