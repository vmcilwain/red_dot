# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe RedDot::RspecResult do
  let(:example_passed) do
    described_class::Example.new(
      description: 'passes', full_description: 'Foo passes', status: :passed,
      file_path: 'spec/foo_spec.rb', line_number: 10, exception_message: nil,
      run_time: 0.1, pending_message: nil
    )
  end
  let(:example_failed) do
    described_class::Example.new(
      description: 'fails', full_description: 'Foo fails', status: :failed,
      file_path: 'spec/foo_spec.rb', line_number: 20, exception_message: 'Expected x',
      run_time: 0.2, pending_message: nil
    )
  end
  let(:example_pending) do
    described_class::Example.new(
      description: 'pending', full_description: 'Foo pending', status: :pending,
      file_path: 'spec/foo_spec.rb', line_number: 30, exception_message: nil,
      run_time: nil, pending_message: 'Not yet'
    )
  end
  let(:examples) { [example_passed, example_failed, example_pending] }
  let(:result) do
    described_class.new(
      summary_line: '3 examples, 1 failure, 1 pending',
      examples: examples,
      duration: 1.5,
      errors_outside_of_examples: 0,
      seed: 12_345
    )
  end

  describe '.from_json_path' do
    it 'returns nil for nil path' do
      expect(described_class.from_json_path(nil)).to be_nil
    end

    it 'returns nil for non-readable path' do
      expect(described_class.from_json_path('/nonexistent')).to be_nil
    end

    it 'returns nil for empty file' do
      f = Tempfile.new(['rspec', '.json'])
      f.write('')
      f.close
      expect(described_class.from_json_path(f.path)).to be_nil
      f.unlink
    end

    it 'parses valid JSON and returns RspecResult' do
      f = Tempfile.new(['rspec', '.json'])
      f.write(<<~JSON)
        {"summary_line":"1 example, 0 failures","examples":[{"description":"ok","full_description":"Foo ok","status":"passed","file_path":"spec/foo_spec.rb","line_number":5,"run_time":0.01}],"summary":{"duration":0.1},"seed":42}
      JSON
      f.close
      r = described_class.from_json_path(f.path)
      expect(r).to be_a(described_class)
      expect(r.summary_line).to eq('1 example, 0 failures')
      expect(r.examples.size).to eq(1)
      expect(r.examples.first.status).to eq(:passed)
      expect(r.duration).to eq(0.1)
      expect(r.seed).to eq(42)
      f.unlink
    end
  end

  describe '#passed_count' do
    it 'counts passed examples' do
      expect(result.passed_count).to eq(1)
    end
  end

  describe '#failed_count' do
    it 'counts failed examples' do
      expect(result.failed_count).to eq(1)
    end
  end

  describe '#pending_count' do
    it 'counts pending examples' do
      expect(result.pending_count).to eq(1)
    end
  end

  describe '#failed_examples' do
    it 'returns only failed examples' do
      expect(result.failed_examples).to eq([example_failed])
    end
  end

  describe '#pending_examples' do
    it 'returns only pending examples' do
      expect(result.pending_examples).to eq([example_pending])
    end
  end

  describe '#failure_locations' do
    it 'returns file:line for failed examples with line_number' do
      expect(result.failure_locations).to eq(['spec/foo_spec.rb:20'])
    end
  end

  describe '#examples_with_run_time' do
    it 'returns examples that have positive run_time' do
      expect(result.examples_with_run_time).to contain_exactly(example_passed, example_failed)
    end
  end

  describe '#slowest_examples' do
    it 'returns up to count examples by run_time descending' do
      expect(result.slowest_examples(2)).to eq([example_failed, example_passed])
    end
  end

  describe '#fastest_examples' do
    it 'returns up to count examples by run_time ascending' do
      expect(result.fastest_examples(2)).to eq([example_passed, example_failed])
    end
  end

  describe '#slowest_files' do
    it 'returns [path, total_sec] for files by total run_time' do
      files = result.slowest_files(5)
      expect(files).to be_an(Array)
      expect(files.first[0]).to eq('spec/foo_spec.rb')
      expect(files.first[1]).to be_within(0.001).of(0.3)
    end
  end
end
