# frozen_string_literal: true

require 'spec_helper'
require 'listen'

RSpec.describe RedDot::FileWatcher do
  describe '.start' do
    it 'returns nil when spec_dirs is empty' do
      result = described_class.start(spec_dirs: [], on_change: proc {})
      expect(result).to be_nil
    end

    it 'returns nil when listen gem is unavailable' do
      allow(described_class).to receive(:require).with('listen').and_raise(LoadError)
      result = described_class.start(spec_dirs: ['/nonexistent'], on_change: proc {})
      expect(result).to be_nil
    end

    context 'with listen available' do
      let(:spec_dir) { Dir.mktmpdir('red_dot_watch') }
      let(:listener_double) { instance_double(Listen::Listener, start: nil, stop: nil, paused?: false) }

      before do
        allow(Listen).to receive(:to).and_return(listener_double)
      end

      after { FileUtils.rm_rf(spec_dir) }

      it 'returns a FileWatcher instance' do
        watcher = described_class.start(spec_dirs: [spec_dir], on_change: proc {})
        expect(watcher).to be_a(described_class)
        watcher.stop
      end

      it 'starts the listener' do
        watcher = described_class.start(spec_dirs: [spec_dir], on_change: proc {})
        expect(listener_double).to have_received(:start)
        watcher.stop
      end
    end
  end

  describe '#stop' do
    it 'stops the listener' do
      listener_double = instance_double(Listen::Listener, start: nil, stop: nil, paused?: false)
      allow(Listen).to receive(:to).and_return(listener_double)
      watcher = described_class.start(spec_dirs: [Dir.tmpdir], on_change: proc {})
      watcher.stop
      expect(listener_double).to have_received(:stop)
    end
  end

  describe '#paused?' do
    it 'delegates to listener' do
      listener_double = instance_double(Listen::Listener, start: nil, stop: nil, paused?: true)
      allow(Listen).to receive(:to).and_return(listener_double)
      watcher = described_class.start(spec_dirs: [Dir.tmpdir], on_change: proc {})
      expect(watcher.paused?).to be true
      watcher.stop
    end
  end
end
