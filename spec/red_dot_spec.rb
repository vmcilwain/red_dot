# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RedDot do
  describe 'VERSION' do
    it 'is set' do
      expect(RedDot::VERSION).to be_a(String)
    end
  end

  describe '.run' do
    it 'requires TTY' do
      allow($stdout).to receive(:tty?).and_return(false)
      allow(Kernel).to receive(:warn)
      expect { RedDot.run }.to raise_error(SystemExit)
    end

    # tty? + Bubbletea.run are required in a non-TTY test env; App is real (tmp dir, no watcher).
    def setup_tty_and_shutdown_spy
      allow($stdout).to receive(:tty?).and_return(true)
      state = {}
      allow(RedDot::App).to receive(:new).and_wrap_original do |orig, **kwargs|
        app = orig.call(**kwargs)
        allow(app).to receive(:shutdown).and_call_original
        state[:app] = app
        app
      end
      state
    end

    it 'shuts down the app after Bubbletea exits' do
      state = setup_tty_and_shutdown_spy
      allow(Bubbletea).to receive(:run)
      Dir.mktmpdir do |tmp|
        RedDot.run(working_dir: tmp, option_overrides: { auto_index: false })
      end
      expect(state[:app]).to have_received(:shutdown)
    end

    it 'shuts down the app when Bubbletea raises' do
      state = setup_tty_and_shutdown_spy
      allow(Bubbletea).to receive(:run).and_raise(StandardError, 'bubbletea failed')
      expect do
        Dir.mktmpdir do |tmp|
          RedDot.run(working_dir: tmp, option_overrides: { auto_index: false })
        end
      end.to raise_error(StandardError, 'bubbletea failed')
      expect(state[:app]).to have_received(:shutdown)
    end
  end
end
