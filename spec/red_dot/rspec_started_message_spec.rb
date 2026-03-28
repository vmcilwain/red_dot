# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RedDot::RspecStartedMessage do
  let(:pid) { 12_345 }
  let(:stdout_io) { instance_double(IO) }
  let(:json_path) { '/tmp/rspec.json' }
  let(:component_root) { 'components/foo' }

  describe '.new' do
    it 'stores pid, stdout_io, json_path' do
      msg = described_class.new(pid: pid, stdout_io: stdout_io, json_path: json_path)
      expect(msg.pid).to eq(pid)
      expect(msg.stdout_io).to eq(stdout_io)
      expect(msg.json_path).to eq(json_path)
    end

    it 'accepts optional component_root' do
      msg = described_class.new(pid: pid, stdout_io: stdout_io, json_path: json_path, component_root: component_root)
      expect(msg.component_root).to eq(component_root)
    end

    it 'allows component_root to be omitted (nil)' do
      msg = described_class.new(pid: pid, stdout_io: stdout_io, json_path: json_path)
      expect(msg.component_root).to be_nil
    end
  end
end
