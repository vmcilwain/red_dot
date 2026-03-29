# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe RedDot::EditorLauncher do
  let(:working_dir) { Dir.mktmpdir('editor_launcher') }

  after { FileUtils.rm_rf(working_dir) }

  it 'does nothing when path is blank' do
    expect(Process).not_to receive(:spawn)
    described_class.open(path: '', working_dir: working_dir, editor: 'cursor')
  end

  it 'does nothing when file does not exist' do
    expect(Process).not_to receive(:spawn)
    described_class.open(path: 'missing.rb', working_dir: working_dir, editor: 'cursor')
  end

  it 'spawns cursor with -g when line given' do
    f = File.join(working_dir, 'a.rb')
    File.write(f, 'x')
    expect(Process).to receive(:spawn).with('cursor', '-g', "#{f}:42", out: File::NULL, err: File::NULL).and_return(123)
    expect(Process).to receive(:detach).with(123)
    described_class.open(path: 'a.rb', line: 42, working_dir: working_dir, editor: 'cursor')
  end

  it 'spawns vscode when editor is vscode' do
    f = File.join(working_dir, 'b.rb')
    File.write(f, 'y')
    expect(Process).to receive(:spawn).with('code', f, out: File::NULL, err: File::NULL).and_return(124)
    expect(Process).to receive(:detach).with(124)
    described_class.open(path: 'b.rb', working_dir: working_dir, editor: 'vscode')
  end
end
