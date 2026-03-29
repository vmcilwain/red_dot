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

  it 'spawns cursor without -g when line is nil' do
    f = File.join(working_dir, 'c.rb')
    File.write(f, 'z')
    expect(Process).to receive(:spawn).with('cursor', f, out: File::NULL, err: File::NULL).and_return(125)
    expect(Process).to receive(:detach).with(125)
    described_class.open(path: 'c.rb', line: nil, working_dir: working_dir, editor: 'cursor')
  end

  it 'spawns mate for textmate with line' do
    f = File.join(working_dir, 'd.rb')
    File.write(f, 'w')
    expect(Process).to receive(:spawn).with('mate', '-l', '7', f, out: File::NULL, err: File::NULL).and_return(126)
    expect(Process).to receive(:detach).with(126)
    described_class.open(path: 'd.rb', line: 7, working_dir: working_dir, editor: 'textmate')
  end

  it 'falls back to cursor when editor is invalid' do
    f = File.join(working_dir, 'e.rb')
    File.write(f, 'v')
    expect(Process).to receive(:spawn).with('cursor', f, out: File::NULL, err: File::NULL).and_return(127)
    expect(Process).to receive(:detach).with(127)
    described_class.open(path: 'e.rb', working_dir: working_dir, editor: 'not_an_editor')
  end

  it 'warns and does not raise when spawn fails' do
    f = File.join(working_dir, 'f.rb')
    File.write(f, 'u')
    expect(Process).to receive(:spawn).and_raise(Errno::ENOENT, 'No such file')
    expect(described_class).to receive(:warn).with(/red_dot: could not open editor/)
    expect { described_class.open(path: 'f.rb', working_dir: working_dir, editor: 'cursor') }.not_to raise_error
  end
end
