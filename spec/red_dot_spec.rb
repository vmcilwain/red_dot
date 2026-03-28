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
  end
end
