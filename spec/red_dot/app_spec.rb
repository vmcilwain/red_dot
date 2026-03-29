# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RedDot::App do
  let(:working_dir) { File.expand_path(Dir.mktmpdir('red_dot_app')) }
  let(:spec_files) { %w[spec/foo_spec.rb spec/bar_spec.rb] }
  let(:grouped) { { 'spec' => spec_files } }
  let(:discovery) do
    instance_double(RedDot::SpecDiscovery,
                    discover: spec_files,
                    discover_grouped_by_dir: grouped,
                    run_context_for: { run_cwd: working_dir, rspec_path: 'spec/foo_spec.rb' },
                    default_run_all_paths: spec_files,
                    empty_state_message: 'No spec files',
                    umbrella?: false)
  end
  let(:options) do
    { tags: [], tags_str: '', format: 'progress', out_path: '', example_filter: '', line_number: '',
      fail_fast: false, full_output: false, seed: '', editor: 'cursor' }
  end

  before do
    allow(RedDot::SpecDiscovery).to receive(:new).with(working_dir: anything).and_return(discovery)
    allow(RedDot::Config).to receive(:load).with(working_dir: anything).and_return(options)
  end

  subject(:app) { described_class.new(working_dir: working_dir) }

  shared_examples 'returns self and nil' do
    it 'returns [self, nil]' do
      expect(result).to eq([app, nil])
    end
  end

  describe '#init' do
    it 'returns [self, nil]' do
      expect(app.init).to eq([app, nil])
    end
  end

  describe '#initialize' do
    it 'discovers spec files and loads config' do
      app
      expect(discovery).to have_received(:discover)
      expect(RedDot::Config).to have_received(:load)
    end

    context 'with option_overrides' do
      it 'applies tags array' do
        a = described_class.new(working_dir: working_dir, option_overrides: { tags: %w[a b] })
        expect(a.send(:instance_variable_get, :@options)[:tags]).to eq(%w[a b])
      end

      it 'applies format' do
        a = described_class.new(working_dir: working_dir, option_overrides: { format: 'documentation' })
        expect(a.send(:instance_variable_get, :@options)[:format]).to eq('documentation')
      end

      it 'applies fail_fast' do
        a = described_class.new(working_dir: working_dir, option_overrides: { fail_fast: true })
        expect(a.send(:instance_variable_get, :@options)[:fail_fast]).to be true
      end

      it 'applies full_output' do
        a = described_class.new(working_dir: working_dir, option_overrides: { full_output: true })
        expect(a.send(:instance_variable_get, :@options)[:full_output]).to be true
      end
    end
  end

  describe '#update' do
    context 'with Bubbletea::WindowSizeMessage' do
      let(:msg) { Bubbletea::WindowSizeMessage.new(width: 100, height: 30) }
      let(:result) { app.update(msg) }

      include_examples 'returns self and nil'

      it 'updates width and height' do
        app.update(msg)
        expect(app.send(:instance_variable_get, :@width)).to eq(100)
        expect(app.send(:instance_variable_get, :@height)).to eq(30)
      end
    end

    context 'with RspecStartedMessage' do
      let(:msg) do
        RedDot::RspecStartedMessage.new(
          pid: 999,
          stdout_io: instance_double(IO),
          json_path: '/tmp/out.json'
        )
      end
      let(:result) { app.update(msg) }

      it 'returns [self, schedule_tick command]' do
        expect(result.size).to eq(2)
        expect(result[0]).to eq(app)
        expect(result[1]).to be_truthy
      end

      it 'switches to running screen' do
        app.update(msg)
        expect(app.send(:instance_variable_get, :@screen)).to eq(:running)
      end
    end

    context 'with Bubbletea::KeyMessage' do
      def key_msg(key)
        Bubbletea::KeyMessage.new(key_type: Bubbletea::KeyMessage::KEY_RUNES, runes: [key.ord])
      end

      it 'does not route results keys through find when find was left active' do
        mk = lambda do |line|
          RedDot::RspecResult::Example.new(
            description: 'fails', full_description: 'x', status: :failed,
            file_path: 'spec/foo_spec.rb', line_number: line, exception_message: 'e',
            run_time: nil, pending_message: nil
          )
        end
        result = RedDot::RspecResult.new(
          summary_line: '2 examples, 2 failures',
          examples: [mk.call(1), mk.call(2)],
          duration: 0.1
        )
        app.send(:instance_variable_set, :@screen, :results)
        app.send(:instance_variable_set, :@find_buffer, 'foo')
        app.send(:instance_variable_set, :@last_result, result)
        app.send(:instance_variable_set, :@results_cursor, 0)
        app.send(:instance_variable_set, :@results_total_lines, 5)
        app.update(key_msg('j'))
        expect(app.send(:instance_variable_get, :@find_buffer)).to eq('foo')
        expect(app.send(:instance_variable_get, :@results_cursor)).to eq(1)
      end

      it 'quits on q' do
        allow(Bubbletea).to receive(:quit)
        app.update(key_msg('q'))
        expect(Bubbletea).to have_received(:quit)
      end

      it 'returns [self, nil] for unhandled key' do
        result = app.update(key_msg('x'))
        expect(result).to eq([app, nil])
      end
    end

    context 'with unknown message' do
      let(:result) { app.update(Object.new) }
      include_examples 'returns self and nil'
    end
  end

  describe '#view' do
    it 'returns a string with newlines' do
      out = app.view
      expect(out).to be_a(String)
      expect(out).to include("\n")
    end

    it 'includes options bar and main area' do
      out = app.view
      expect(out.lines.size).to be >= 5
    end
  end

  describe '#apply_option_overrides' do
    def app_options
      app.send(:instance_variable_get, :@options)
    end

    it 'applies tags array and sets tags_str' do
      app.send(:apply_option_overrides, { tags: %w[foo bar] })
      expect(app_options[:tags]).to eq(%w[foo bar])
      expect(app_options[:tags_str]).to eq('foo, bar')
    end

    it 'ignores nil or empty overrides' do
      app.send(:apply_option_overrides, nil)
      app.send(:apply_option_overrides, {})
      expect(app_options[:format]).to eq('progress')
    end

    it 'applies full_output' do
      app.send(:apply_option_overrides, { full_output: true })
      expect(app_options[:full_output]).to be true
    end

    it 'sets editor only when valid' do
      app.send(:apply_option_overrides, { editor: 'vscode' })
      expect(app_options[:editor]).to eq('vscode')
    end

    it 'ignores invalid editor' do
      orig = app_options[:editor]
      app.send(:apply_option_overrides, { editor: 'invalid' })
      expect(app_options[:editor]).to eq(orig)
    end
  end

  describe 'private helpers (via send for unit coverage)' do
    describe '#visible_length' do
      it 'strips ANSI codes' do
        expect(app.send(:visible_length, "\e[31mhi\e[0m")).to eq(2)
      end
    end

    describe '#truncate_plain' do
      it 'truncates to max_w' do
        expect(app.send(:truncate_plain, 'hello world', 5)).to eq('hello')
      end

      it 'strips ANSI before measuring' do
        s = "\e[31mhi\e[0m"
        expect(app.send(:truncate_plain, s, 2)).to eq('hi')
      end
    end

    describe '#format_run_time' do
      it 'formats ms for sub-second' do
        expect(app.send(:format_run_time, 0.5)).to eq('500ms')
      end

      it 'formats seconds' do
        expect(app.send(:format_run_time, 1.5)).to eq('1.5s')
      end

      it 'returns empty string for non-numeric' do
        expect(app.send(:format_run_time, nil)).to eq('')
      end
    end

    describe '#expand_selected_paths_for_run' do
      it 'prefers whole file over line keys for the same file' do
        expect(app.send(:expand_selected_paths_for_run, %w[spec/a_spec.rb spec/a_spec.rb:10 spec/b_spec.rb:2])).to eq(
          %w[spec/a_spec.rb spec/b_spec.rb:2]
        )
      end
    end

    describe '#toggle_row_selection' do
      let(:file_row) { RedDot::DisplayRow.new(type: :file, path: 'spec/foo_spec.rb', line_number: nil, full_description: nil) }
      let(:example_row) do
        RedDot::DisplayRow.new(type: :example, path: 'spec/foo_spec.rb', line_number: 10, full_description: 'does x')
      end

      it 'selecting a file clears line-level keys for that file' do
        app.send(:instance_variable_set, :@selected, { 'spec/foo_spec.rb:10' => true })
        app.send(:toggle_row_selection, file_row)
        expect(app.send(:instance_variable_get, :@selected)).to eq('spec/foo_spec.rb' => true)
      end

      it 'selecting an example clears whole-file selection for that path' do
        app.send(:instance_variable_set, :@selected, { 'spec/foo_spec.rb' => true })
        app.send(:toggle_row_selection, example_row)
        expect(app.send(:instance_variable_get, :@selected)['spec/foo_spec.rb']).to be false
        expect(app.send(:instance_variable_get, :@selected)['spec/foo_spec.rb:10']).to be true
      end
    end
  end
end
