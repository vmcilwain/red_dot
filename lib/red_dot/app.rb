# frozen_string_literal: true

require 'bubbletea'
require 'lipgloss'

module RedDot
  DisplayRow = Struct.new(:type, :path, :line_number, :full_description, keyword_init: true) do
    def file_row?
      type == :file
    end

    def example_row?
      type == :example
    end

    def runnable_path
      example_row? ? "#{path}:#{line_number}" : path
    end

    def row_id
      example_row? ? "#{path}:#{line_number}" : path
    end
  end

  class RspecStartedMessage < Bubbletea::Message
    attr_reader :pid, :stdout_io, :json_path, :component_root

    def initialize(pid:, stdout_io:, json_path:, component_root: nil)
      @pid = pid
      @stdout_io = stdout_io
      @json_path = json_path
      @component_root = component_root
    end
  end

  class TickMessage < Bubbletea::Message; end

  class App
    include Bubbletea::Model

    LEFT_PANEL_RATIO = 0.38
    OPTIONS_BAR_HEIGHT = 5
    STATUS_HEIGHT = 1

    def initialize(working_dir: Dir.pwd, option_overrides: {})
      @working_dir = File.expand_path(working_dir)
      @discovery = SpecDiscovery.new(working_dir: @working_dir)
      @spec_files = @discovery.discover
      @grouped = @discovery.discover_grouped_by_dir
      @cursor = 0
      @selected = {}
      @expanded_files = Set.new
      @examples_by_file = {}
      @screen = :file_list
      @options = Config.load(working_dir: @working_dir)
      apply_option_overrides(option_overrides)
      @run_pid = nil
      @run_stdout = nil
      @run_json_path = nil
      @run_output = []
      @run_output_scroll = 0
      @last_result = nil
      @last_run_paths = nil
      @last_run_component_root = nil
      @run_failed_paths = nil
      @run_queue = nil
      @width = 80
      @height = 24
      @options_cursor = 0
      @options_editing = nil
      @options_edit_buffer = ''
      @options_field_keys = %i[line_number seed format fail_fast tags_str out_path example_filter editor]
      @results_cursor = 0
      @file_list_scroll_offset = 0
      @results_scroll_offset = 0
      @results_failed_line_indices = []
      @results_total_lines = 0
      @input_prompt = nil
      @find_buffer = nil
      @options_focus = false
      @index_files = []
      @index_current = 0
      @index_total = 0
      @find_index_hint_shown = false
      setup_styles
    end

    def init
      [self, nil]
    end

    def apply_option_overrides(overrides)
      return if overrides.nil? || overrides.empty?

      o = overrides
      if o.key?(:tags) && o[:tags].is_a?(Array)
        @options[:tags] = o[:tags].map(&:to_s).reject(&:empty?)
        @options[:tags_str] = @options[:tags].join(', ')
      end
      @options[:tags_str] = o[:tags_str].to_s if o.key?(:tags_str)
      @options[:format] = o[:format].to_s.strip if o.key?(:format) && !o[:format].to_s.strip.empty?
      @options[:out_path] = o[:out_path].to_s if o.key?(:out_path)
      @options[:example_filter] = o[:example_filter].to_s if o.key?(:example_filter)
      @options[:line_number] = o[:line_number].to_s if o.key?(:line_number)
      @options[:fail_fast] = o[:fail_fast] ? true : false if o.key?(:fail_fast)
      @options[:seed] = o[:seed].to_s if o.key?(:seed)
      return unless o.key?(:editor) && RedDot::Config::VALID_EDITORS.include?(o[:editor].to_s.strip.downcase)

      @options[:editor] = o[:editor].to_s.strip.downcase
    end

    def update(message)
      case message
      when Bubbletea::WindowSizeMessage
        @width = message.width
        @height = message.height
        [self, nil]
      when RspecStartedMessage
        @run_pid = message.pid
        @run_stdout = message.stdout_io
        @run_json_path = message.json_path
        @last_run_component_root = message.component_root if message.respond_to?(:component_root) && message.component_root
        @run_output = []
        @run_output_scroll = 0
        @screen = :running
        [self, schedule_tick]
      when TickMessage
        if @screen == :indexing && @index_current < @index_total
          path = @index_files[@index_current]
          load_examples_for(path)
          @index_current += 1
          if @index_current >= @index_total
            @screen = :file_list
            [self, nil]
          else
            [self, schedule_tick]
          end
        elsif @screen == :running && @run_pid
          read_run_output
          pid_done = Process.wait(@run_pid, Process::WNOHANG) rescue nil
          if pid_done
            drain_run_output
            @run_stdout&.close
            @run_stdout = nil
            @run_pid = nil
            if @run_queue&.any?
              next_group = @run_queue.shift
              opts = { working_dir: next_group[:run_cwd], paths: next_group[:rspec_paths],
                       tags: @options[:tags].empty? ? parse_tags(@options[:tags_str]) : @options[:tags],
                       format: @options[:format], out_path: @options[:out_path].to_s.strip,
                       example_filter: @options[:example_filter].to_s.strip, fail_fast: @options[:fail_fast],
                       seed: @options[:seed].to_s.strip }
              opts[:out_path] = nil if opts[:out_path].to_s.empty?
              opts[:example_filter] = nil if opts[:example_filter].to_s.empty?
              opts[:seed] = nil if opts[:seed].to_s.empty?
              data = RspecRunner.spawn(**opts)
              @run_pid = data[:pid]
              @run_stdout = data[:stdout_io]
              @run_json_path = data[:json_path]
              @last_run_component_root = next_group[:component_root]
              [self, schedule_tick]
            else
              @run_queue = nil
              @last_result = RspecResult.from_json_path(@run_json_path)
              raw_failures = @last_result&.failure_locations || []
              @run_failed_paths = normalize_failure_paths(raw_failures)
              @screen = :results
              @results_cursor = 0
              @results_scroll_offset = 0
              [self, nil]
            end
          else
            [self, schedule_tick]
          end
        else
          [self, nil]
        end
      when Bubbletea::KeyMessage
        handle_key(message)
      else
        [self, nil]
      end
    end

    def view
      content_h = [@height - STATUS_HEIGHT - OPTIONS_BAR_HEIGHT, 5].max
      left_w = [(LEFT_PANEL_RATIO * @width).floor, 24].max
      center_w = [@width - left_w - 1, 20].max

      options_bar_lines = build_options_bar_lines
      left_lines = build_file_list_lines(content_h)
      center_lines = build_center_panel_lines(content_h)

      options_bar = options_bar_lines.map { |line| pad_line(truncate_line(line, @width), @width) }.first(OPTIONS_BAR_HEIGHT)
      options_bar += Array.new([OPTIONS_BAR_HEIGHT - options_bar.size, 0].max) { ' ' * @width }

      left_block = block_to_size(left_lines, left_w, content_h)
      center_block = block_to_size(center_lines, center_w, content_h)

      sep_char = '│'
      sep = [2, 3].include?(focused_panel) ? @active_title_style.render(sep_char) : @inactive_title_style.render(sep_char)
      left_arr = left_block.split("\n")
      center_arr = center_block.split("\n")
      main_rows = content_h.times.map do |i|
        l = left_arr[i] || ''.ljust(left_w)
        c = center_arr[i] || ''.ljust(center_w)
        "#{l}#{sep}#{c}"
      end
      status = @help_style.render(truncate_plain(status_line, @width).ljust(@width))
      [options_bar.join("\n"), main_rows.join("\n"), status].join("\n")
    end

    private

    def setup_styles
      @active_title_style = Lipgloss::Style.new.bold(true).foreground('2')
      @inactive_title_style = Lipgloss::Style.new.foreground('241')
      @help_style = Lipgloss::Style.new.foreground('12')
      @pass_style = Lipgloss::Style.new.foreground('2').bold(true)
      @fail_style = Lipgloss::Style.new.foreground('9')
      @warn_style = Lipgloss::Style.new.foreground('11').bold(true)
      @muted_style = Lipgloss::Style.new.foreground('241')
      @selected_style = Lipgloss::Style.new.foreground('255').background('4')
      @cursor_style = Lipgloss::Style.new.foreground('255').background('4').bold(true)
    end

    def focused_panel
      return 1 if @options_focus
      return 3 if @screen == :results || @screen == :running || @screen == :indexing

      2
    end

    def schedule_tick
      Bubbletea.tick(0.05) { TickMessage.new }
    end

    def handle_key(message)
      return handle_input_prompt_key(message) if @input_prompt
      return handle_find_key(message) if @find_buffer

      key = message.to_s
      unless @options_editing
        case key
        when '1'
          @options_focus = true
          @screen = :file_list
          return [self, nil]
        when '2'
          @options_focus = false
          @screen = :file_list
          return [self, nil]
        when '3'
          @options_focus = false
          if @run_pid
            @screen = :running
          elsif @last_result
            @screen = :results
          end
          return [self, nil]
        end
      end
      return handle_options_key(key, message) if @options_focus

      case @screen
      when :file_list
        handle_file_list_key(key, message)
      when :indexing
        if ['q', 'ctrl+c', 'esc'].include?(key)
          @screen = :file_list
          @index_current = @index_total
        end
        [self, nil]
      when :running
        handle_running_key(key)
      when :results
        handle_results_key(key)
      else
        [self, nil]
      end
    end

    def file_list_visible_height(content_h)
      header_count = 2
      header_count += 1 if @find_buffer
      header_count += 1 if @find_buffer && index_empty? && !@find_index_hint_shown
      [content_h - header_count, 1].max
    end

    def handle_file_list_key(key, _message = nil)
      list = display_rows
      row = list[@cursor]
      content_h = [@height - STATUS_HEIGHT - OPTIONS_BAR_HEIGHT, 5].max
      visible_list_height = file_list_visible_height(content_h)
      max_scroll = [list.size - visible_list_height, 0].max
      case key
      when 'q', 'ctrl+c', 'esc'
        kill_run if @run_pid
        [self, Bubbletea.quit]
      when '/'
        @find_buffer = ''
        @cursor = 0
        @file_list_scroll_offset = 0
        [self, nil]
      when 'up', 'k'
        max_idx = [list.size - 1, 0].max
        @cursor = [[@cursor - 1, 0].max, max_idx].min
        [self, nil]
      when 'down', 'j'
        max_idx = [list.size - 1, 0].max
        @cursor = [[@cursor + 1, max_idx].min, 0].max
        [self, nil]
      when 'pgup', 'ctrl+u'
        @cursor = [@cursor - visible_list_height, 0].max
        @file_list_scroll_offset = [@file_list_scroll_offset - visible_list_height, 0].max
        [self, nil]
      when 'pgdown', 'ctrl+d'
        @cursor = [@cursor + visible_list_height, [list.size - 1, 0].max].min
        @file_list_scroll_offset = [@file_list_scroll_offset + visible_list_height, max_scroll].min
        [self, nil]
      when 'home', 'g'
        @cursor = 0
        @file_list_scroll_offset = 0
        [self, nil]
      when 'end', 'G'
        @cursor = [list.size - 1, 0].max
        @file_list_scroll_offset = max_scroll
        [self, nil]
      when 'right'
        if row&.file_row?
          path = row.path
          if @expanded_files.include?(path)
            @expanded_files.delete(path)
          else
            load_examples_for(path)
            @expanded_files.add(path)
          end
          list = display_rows
          @cursor = [@cursor, list.size - 1].min
        end
        [self, nil]
      when 'left'
        if row&.example_row?
          path = row.path
          parent_idx = (0...@cursor).to_a.rindex { |i| list[i].file_row? && list[i].path == path }
          @cursor = parent_idx if parent_idx
          row = list[@cursor]
        end
        if row&.file_row?
          @expanded_files.delete(row.path)
          list = display_rows
          @cursor = [@cursor, list.size - 1].min
        end
        [self, nil]
      when ']'
        flat_spec_list.each { |path| @expanded_files.add(path) }
        list = display_rows
        @cursor = [@cursor, list.size - 1].min
        [self, nil]
      when '['
        @expanded_files.clear
        list = display_rows
        @cursor = [@cursor, list.size - 1].min
        [self, nil]
      when ' ', 'space'
        @selected[row.path] = !@selected[row.path] if row&.file_row?
        [self, nil]
      when 'enter'
        run_specs(paths_for_run)
      when 'a'
        run_specs(flat_spec_list.empty? ? @discovery.default_run_all_paths : flat_spec_list)
      when 's'
        run_specs(paths_for_run)
      when 'f'
        return run_specs(@run_failed_paths) if @run_failed_paths&.any?

        [self, nil]
      when 'e'
        if row&.example_row?
          run_specs([row.runnable_path])
        elsif row&.file_row?
          @input_prompt = { message: 'Line number (e.g. 42): ', buffer: '', file: row.path }
        end
        [self, nil]
      when 'O'
        open_in_editor(row&.path, row&.example_row? ? row.line_number : nil) if row
        [self, nil]
      when 'o'
        @options_focus = true
        [self, nil]
      when 'R'
        refresh_spec_list
        [self, nil]
      when 'I'
        files = flat_spec_list
        if files.empty?
          [self, nil]
        else
          @screen = :indexing
          @index_files = files
          @index_current = 0
          @index_total = files.size
          [self, schedule_tick]
        end
      else
        [self, nil]
      end
    end

    def handle_find_key(message)
      list = display_rows
      if message.respond_to?(:backspace?) && message.backspace?
        @find_buffer = @find_buffer[0, [@find_buffer.length - 1, 0].max]
        @cursor = [@cursor, list.size - 1].min
        @cursor = 0 if list.size.positive? && @cursor.negative?
        return [self, nil]
      end
      if message.respond_to?(:enter?) && message.enter?
        row = list[@cursor]
        return run_specs([row.runnable_path]) if row

        return [self, nil]
      end
      key = message.to_s
      if (message.respond_to?(:esc?) && message.esc?) || key == 'ctrl+b'
        sync_cursor_to_full_list
        @expanded_files.clear
        @find_buffer = nil
        return [self, nil]
      end
      content_h = [@height - STATUS_HEIGHT - OPTIONS_BAR_HEIGHT, 5].max
      visible_list_height = file_list_visible_height(content_h)
      max_scroll = [list.size - visible_list_height, 0].max
      case key
      when 'up'
        max_idx = [list.size - 1, 0].max
        @cursor = [[@cursor - 1, 0].max, max_idx].min
        return [self, nil]
      when 'down'
        max_idx = [list.size - 1, 0].max
        @cursor = [[@cursor + 1, max_idx].min, 0].max
        return [self, nil]
      when 'pgup', 'ctrl+u'
        @cursor = [@cursor - visible_list_height, 0].max
        @file_list_scroll_offset = [@file_list_scroll_offset - visible_list_height, 0].max
        return [self, nil]
      when 'pgdown', 'ctrl+d'
        @cursor = [@cursor + visible_list_height, [list.size - 1, 0].max].min
        @file_list_scroll_offset = [@file_list_scroll_offset + visible_list_height, max_scroll].min
        return [self, nil]
      when 'home'
        @cursor = 0
        @file_list_scroll_offset = 0
        return [self, nil]
      when 'end'
        @cursor = [list.size - 1, 0].max
        @file_list_scroll_offset = max_scroll
        return [self, nil]
      end
      c = nil
      if message.respond_to?(:char) && (ch = message.char) && ch.is_a?(String) && !ch.empty?
        c = ch
      elsif key.length == 1 && key.match?(/\S/)
        c = key
      end
      if c
        @find_buffer += c
        list = display_rows
        @cursor = 0 if list.any? && (@cursor >= list.size || @cursor.negative?)
        @cursor = [@cursor, list.size - 1].min
        return [self, nil]
      end
      [self, nil]
    end

    def sync_cursor_to_full_list
      return if @find_buffer.nil?

      row = display_rows[@cursor]
      return unless row

      full = build_full_display_rows
      idx = full.find_index { |r| r.row_id == row.row_id }
      @cursor = idx if idx
      max_idx = [full.size - 1, 0].max
      @cursor = [[@cursor, max_idx].min, 0].max
    end

    def handle_input_prompt_key(message)
      if message.respond_to?(:backspace?) && message.backspace?
        buf = @input_prompt[:buffer]
        @input_prompt = @input_prompt.merge(buffer: buf[0, buf.length - 1].to_s)
        return [self, nil]
      end
      if message.respond_to?(:enter?) && message.enter?
        line = @input_prompt[:buffer].strip
        file = @input_prompt[:file]
        @input_prompt = nil
        path = line.to_i.positive? ? "#{file}:#{line}" : file
        return run_specs([path])
      end
      if message.respond_to?(:esc?) && message.esc?
        @input_prompt = nil
        return [self, nil]
      end
      if message.respond_to?(:char) && (c = message.char) && c.is_a?(String) && !c.empty?
        @input_prompt = @input_prompt.merge(buffer: @input_prompt[:buffer] + c)
        return [self, nil]
      end
      [self, nil]
    end

    def handle_options_key(key, message)
      return handle_options_edit_key(key, message) if @options_editing

      case key
      when 'q', 'ctrl+c'
        [self, Bubbletea.quit]
      when 'esc', 'b'
        @options_focus = false
        [self, nil]
      when 'left', 'up', 'k'
        max_opt = @options_field_keys.length - 1
        @options_cursor = [[@options_cursor - 1, 0].max, max_opt].min
        [self, nil]
      when 'right', 'down', 'j'
        max_opt = @options_field_keys.length - 1
        @options_cursor = [[@options_cursor + 1, max_opt].min, 0].max
        [self, nil]
      when 'enter'
        field = @options_field_keys[@options_cursor]
        if field == :fail_fast
          @options[:fail_fast] = !@options[:fail_fast]
        elsif field == :editor
          idx = RedDot::Config::VALID_EDITORS.index(@options[:editor].to_s) || 0
          @options[:editor] = RedDot::Config::VALID_EDITORS[(idx + 1) % RedDot::Config::VALID_EDITORS.size]
        else
          @options_editing = field
          @options_edit_buffer = @options[field].to_s.dup
        end
        [self, nil]
      else
        [self, nil]
      end
    end

    def handle_options_edit_key(key, message)
      if message.respond_to?(:backspace?) && message.backspace?
        @options_edit_buffer = @options_edit_buffer[0, [@options_edit_buffer.length - 1, 0].max].to_s
        return [self, nil]
      end
      if message.respond_to?(:enter?) && message.enter?
        field = @options_editing
        @options_editing = nil
        @options[field] = @options_edit_buffer.dup
        @options[:tags] = parse_tags(@options[:tags_str]) if field == :tags_str
        [self, nil]
      end
      if message.respond_to?(:esc?) && message.esc?
        @options_editing = nil
        [self, nil]
      end
      if message.respond_to?(:char) && (c = message.char) && c.is_a?(String) && !c.empty?
        @options_edit_buffer += c
        [self, nil]
      end
      [self, nil]
    end

    def run_output_visible_height(content_h)
      [content_h - 4, 1].max
    end

    def handle_running_key(key)
      content_h = [@height - STATUS_HEIGHT - OPTIONS_BAR_HEIGHT, 5].max
      run_visible = run_output_visible_height(content_h)
      max_scroll = [@run_output.size - run_visible, 0].max
      case key
      when 'q', 'ctrl+c'
        kill_run
        @screen = :file_list
        [self, nil]
      when '2'
        @screen = :file_list
        [self, nil]
      when 'up', 'k'
        @run_output_scroll = [@run_output_scroll - 1, 0].max
        [self, nil]
      when 'down', 'j'
        @run_output_scroll = [@run_output_scroll + 1, max_scroll].min
        [self, nil]
      when 'pgup', 'ctrl+u'
        @run_output_scroll = [@run_output_scroll - run_visible, 0].max
        [self, nil]
      when 'pgdown', 'ctrl+d'
        @run_output_scroll = [@run_output_scroll + run_visible, max_scroll].min
        [self, nil]
      when 'home', 'g'
        @run_output_scroll = 0
        [self, nil]
      when 'end', 'G'
        @run_output_scroll = max_scroll
        [self, nil]
      else
        [self, nil]
      end
    end

    def handle_results_key(key)
      failed = @last_result&.failed_examples || []
      content_h = [@height - STATUS_HEIGHT - OPTIONS_BAR_HEIGHT, 5].max
      case key
      when 'q', 'ctrl+c'
        [self, Bubbletea.quit]
      when 'esc', 'b'
        @screen = :file_list
        [self, nil]
      when 'up', 'k'
        @results_cursor = [[@results_cursor - 1, 0].max, [failed.length - 1, 0].max].min
        [self, nil]
      when 'down', 'j'
        @results_cursor = [[@results_cursor + 1, failed.length - 1].min, 0].max
        [self, nil]
      when 'pgup', 'ctrl+u'
        @results_scroll_offset = [@results_scroll_offset - content_h, 0].max
        [self, nil]
      when 'pgdown', 'ctrl+d'
        max_scroll = [@results_total_lines - content_h, 0].max
        @results_scroll_offset = [@results_scroll_offset + content_h, max_scroll].min
        [self, nil]
      when 'home', 'g'
        @results_scroll_offset = 0
        @results_cursor = 0
        [self, nil]
      when 'end', 'G'
        max_scroll = [@results_total_lines - content_h, 0].max
        @results_scroll_offset = max_scroll
        @results_cursor = [failed.length - 1, 0].max
        [self, nil]
      when 'e'
        ex = failed[@results_cursor]
        if ex&.line_number
          display_path = display_path_for_result_file(ex.file_path)
          return run_specs(["#{display_path}:#{ex.line_number}"])
        end
        [self, nil]
      when 'O'
        ex = failed[@results_cursor]
        if ex
          display_path = display_path_for_result_file(ex.file_path)
          open_in_editor(display_path, ex.line_number)
        end
        [self, nil]
      when 'r'
        run_specs(@last_run_paths || @discovery.default_run_all_paths)
      when 'f'
        return run_specs(@run_failed_paths) if @run_failed_paths&.any?

        [self, nil]
      else
        [self, nil]
      end
    end

    def flat_spec_list
      @grouped.flat_map { |_dir, files| files }
    end

    def fuzzy_match(paths, query)
      return paths if query.to_s.strip.empty?

      q = query.to_s.downcase
      paths.select { |path| fuzzy_match_string(path, q) }
    end

    def fuzzy_match_string(str, query)
      return true if query.to_s.strip.empty?

      q = query.to_s.downcase
      s = str.to_s.downcase
      j = 0
      s.each_char do |c|
        j += 1 if j < q.length && c == q[j]
      end
      j == q.length
    end

    def load_examples_for(path)
      return @examples_by_file[path] if @examples_by_file.key?(path)

      ctx = @discovery.run_context_for(path)
      run_cwd = ctx[:run_cwd]
      rspec_path = ctx[:rspec_path]
      examples = ExampleDiscovery.get_cached_examples(run_cwd, rspec_path)
      examples = ExampleDiscovery.discover(working_dir: run_cwd, path: rspec_path) if examples.nil?
      @examples_by_file[path] = examples
      examples
    end

    def build_full_display_rows
      rows = []
      flat_spec_list.each do |path|
        rows << DisplayRow.new(type: :file, path: path, line_number: nil, full_description: nil)
        next unless @expanded_files.include?(path)

        load_examples_for(path).each do |ex|
          rows << DisplayRow.new(
            type: :example,
            path: path,
            line_number: ex.line_number,
            full_description: ex.full_description
          )
        end
      end
      rows
    end

    def cached_examples_for(path)
      return @examples_by_file[path] if @examples_by_file.key?(path)

      ctx = @discovery.run_context_for(path)
      examples = ExampleDiscovery.get_cached_examples(ctx[:run_cwd], ctx[:rspec_path])
      examples || []
    end

    def build_filtered_display_rows
      q = @find_buffer.to_s.strip.downcase
      return build_full_display_rows if q.empty?

      rows = []
      flat_spec_list.each do |path|
        file_matches = fuzzy_match_string(path, q)
        examples = cached_examples_for(path)
        example_matches = examples.select { |ex| fuzzy_match_string(ex.full_description.to_s, q) }
        show_file = file_matches || example_matches.any?
        next unless show_file

        @expanded_files.add(path) if example_matches.any?
        rows << DisplayRow.new(type: :file, path: path, line_number: nil, full_description: nil)
        examples_to_show = file_matches ? examples : example_matches
        examples_to_show.each do |ex|
          rows << DisplayRow.new(
            type: :example,
            path: path,
            line_number: ex.line_number,
            full_description: ex.full_description
          )
        end
      end
      rows
    end

    def display_rows
      if @find_buffer.nil? || @find_buffer.to_s.strip.empty?
        build_full_display_rows
      else
        build_filtered_display_rows
      end
    end

    def current_spec_list
      display_rows
    end

    def paths_for_run
      selected = @selected.select { |_, v| v }.keys
      if selected.any?
        selected.sort
      else
        row = display_rows[@cursor]
        if row
          [row.runnable_path]
        else
          @discovery.default_run_all_paths
        end
      end
    end

    def apply_line_number_to_paths(paths)
      line = @options[:line_number].to_s.strip
      return paths if line.empty?
      return paths unless paths.size == 1 && paths[0].to_s !~ /:\d+\z/
      return paths unless line.match?(/\A\d+\z/)

      ["#{paths[0]}:#{line}"]
    end

    def run_specs(paths)
      paths = apply_line_number_to_paths(paths)
      @last_run_paths = paths
      tags = @options[:tags].empty? ? parse_tags(@options[:tags_str]) : @options[:tags]
      format = @options[:format]
      out_path = @options[:out_path].to_s.strip
      out_path = nil if out_path.empty?
      example_filter = @options[:example_filter].to_s.strip
      example_filter = nil if example_filter.empty?
      seed = @options[:seed].to_s.strip
      seed = nil if seed.empty?

      groups = group_paths_by_run_context(paths)
      if groups.size == 1
        g = groups.first
        opts = { working_dir: g[:run_cwd], paths: g[:rspec_paths], tags: tags, format: format,
                 out_path: out_path, example_filter: example_filter, fail_fast: @options[:fail_fast], seed: seed }
        proc = lambda do
          data = RspecRunner.spawn(**opts)
          RspecStartedMessage.new(pid: data[:pid], stdout_io: data[:stdout_io], json_path: data[:json_path],
                                  component_root: g[:component_root])
        end
        return [self, proc]
      end

      @run_queue = groups
      first = @run_queue.shift
      opts = { working_dir: first[:run_cwd], paths: first[:rspec_paths], tags: tags, format: format,
               out_path: out_path, example_filter: example_filter, fail_fast: @options[:fail_fast], seed: seed }
      proc = lambda do
        data = RspecRunner.spawn(**opts)
        RspecStartedMessage.new(pid: data[:pid], stdout_io: data[:stdout_io], json_path: data[:json_path],
                                component_root: first[:component_root])
      end
      [self, proc]
    end

    def group_paths_by_run_context(paths)
      by_cwd = Hash.new { |h, k| h[k] = { run_cwd: k, rspec_paths: [], component_root: nil } }
      paths.each do |display_path|
        ctx = @discovery.run_context_for(display_path)
        run_cwd = ctx[:run_cwd]
        rspec_path = ctx[:rspec_path]
        component_root = @discovery.umbrella? ? relative_component_root(run_cwd) : nil
        by_cwd[run_cwd][:rspec_paths] << rspec_path
        by_cwd[run_cwd][:component_root] = component_root
      end
      by_cwd.values
    end

    def relative_component_root(run_cwd)
      return '' if run_cwd == @working_dir

      Pathname.new(run_cwd).relative_path_from(Pathname.new(@working_dir)).to_s
    end

    def normalize_failure_paths(locations)
      return locations if locations.nil? || locations.empty?
      return locations unless @last_run_component_root

      locations.map do |loc|
        if loc.to_s.include?(':')
          file, line = loc.to_s.split(':', 2)
          display_file = @last_run_component_root.empty? ? file : "#{@last_run_component_root}/#{file}"
          "#{display_file}:#{line}"
        else
          @last_run_component_root.empty? ? loc : "#{@last_run_component_root}/#{loc}"
        end
      end
    end

    def display_path_for_result_file(file_path)
      return file_path.to_s if file_path.to_s.strip.empty?
      return file_path.to_s unless @last_run_component_root

      if @last_run_component_root.empty?
        file_path.to_s
      else
        "#{@last_run_component_root}/#{file_path}"
      end
    end

    def parse_tags(str)
      return [] if str.to_s.strip.empty?

      str.split(/[\s,]+/).map(&:strip).reject(&:empty?)
    end

    def read_run_output
      return unless @run_stdout

      content_h = [@height - STATUS_HEIGHT - OPTIONS_BAR_HEIGHT, 5].max
      run_visible = run_output_visible_height(content_h)
      was_at_bottom = @run_output.size <= run_visible || @run_output_scroll >= [@run_output.size - run_visible, 0].max

      @run_stdout.read_nonblock(4096).each_line do |line|
        @run_output << line.chomp
      end

      return unless was_at_bottom

      max_scroll = [@run_output.size - run_visible, 0].max
      @run_output_scroll = max_scroll
    rescue IO::WaitReadable, EOFError
      # no more data
    end

    def drain_run_output
      return unless @run_stdout

      content_h = [@height - STATUS_HEIGHT - OPTIONS_BAR_HEIGHT, 5].max
      run_visible = run_output_visible_height(content_h)
      was_at_bottom = @run_output.size <= run_visible || @run_output_scroll >= [@run_output.size - run_visible, 0].max

      loop do
        chunk = @run_stdout.read(4096)
        break if chunk.nil? || chunk.empty?

        chunk.each_line do |line|
          @run_output << line.chomp
        end
      end

      return unless was_at_bottom

      max_scroll = [@run_output.size - run_visible, 0].max
      @run_output_scroll = max_scroll
    rescue IOError, Errno::EPIPE
      # pipe closed or broken
    end

    def kill_run
      return unless @run_pid

      Process.kill('TERM', @run_pid) rescue nil
      Process.wait(@run_pid) rescue nil
      drain_run_output
      @run_stdout&.close
      @run_stdout = nil
      @run_pid = nil
      @run_queue = nil
    end

    def refresh_spec_list
      @spec_files = @discovery.discover
      @grouped = @discovery.discover_grouped_by_dir
      @expanded_files = Set.new
      @examples_by_file = {}
      @find_buffer = nil
      @cursor = 0
      [self, nil]
    end

    def open_in_editor(path, line = nil)
      return if path.to_s.strip.empty?

      full_path = File.expand_path(path, @working_dir)
      return unless File.exist?(full_path)

      editor = (@options[:editor] || 'cursor').to_s.downcase
      editor = 'cursor' unless RedDot::Config::VALID_EDITORS.include?(editor)

      args = case editor
             when 'vscode'
               line ? ['code', '-g', "#{full_path}:#{line}"] : ['code', full_path]
             when 'cursor'
               line ? ['cursor', '-g', "#{full_path}:#{line}"] : ['cursor', full_path]
             when 'textmate'
               line ? ['mate', '-l', line.to_s, full_path] : ['mate', full_path]
             else
               ['cursor', full_path]
             end

      pid = Process.spawn(*args, out: File::NULL, err: File::NULL)
      Process.detach(pid)
    end

    def visible_length(str)
      str.to_s.gsub(/\e\[[0-9;]*m/, '').length
    end

    def truncate_line(str, max_w)
      return str.to_s if visible_length(str) <= max_w

      out = +''
      len = 0
      i = 0
      s = str.to_s
      while i < s.length
        if s[i] == "\e" && s[i + 1] == '['
          j = s.index('m', i)
          i = j ? j + 1 : s.length
        else
          break if len >= max_w

          len += 1
          out << s[i]
          i += 1
        end
      end
      out
    end

    def pad_line(str, width)
      str.to_s + (' ' * [width - visible_length(str), 0].max)
    end

    def block_to_size(lines, width, height)
      truncated = lines.first(height).map { |line| pad_line(truncate_line(line, width), width) }
      padding = [height - truncated.size, 0].max
      (truncated + Array.new(padding) { ' ' * width }).join("\n")
    end

    def index_empty?
      @examples_by_file.empty? && ExampleDiscovery.read_cache_file(@working_dir).empty?
    end

    def build_file_list_lines(content_h)
      header_lines = []
      title = @find_buffer ? ' 2  Find ' : ' 2  Spec files '
      header_lines << (focused_panel == 2 ? @active_title_style.render(title) : @inactive_title_style.render(title))
      header_lines << @muted_style.render("  Find: #{@find_buffer}_") if @find_buffer
      if @find_buffer && index_empty? && !@find_index_hint_shown
        header_lines << @muted_style.render('  No index yet — press I to index for test name search.')
        @find_index_hint_shown = true
      end
      header_lines << ''
      list = display_rows
      if list.empty?
        header_lines << (@find_buffer.to_s.strip.empty? ? @muted_style.render("  #{@discovery.empty_state_message}") : @muted_style.render('  No matches'))
        return header_lines
      end
      @cursor = [@cursor, list.size - 1].min
      visible_list_height = [content_h - header_lines.size, 1].max
      max_scroll = [list.size - visible_list_height, 0].max
      @file_list_scroll_offset = [[@file_list_scroll_offset, max_scroll].min, 0].max
      @file_list_scroll_offset = @cursor if @cursor < @file_list_scroll_offset
      @file_list_scroll_offset = @cursor - visible_list_height + 1 if @cursor >= @file_list_scroll_offset + visible_list_height
      visible_rows = list[@file_list_scroll_offset, visible_list_height] || []
      list_lines = visible_rows.each_with_index.map do |row, i|
        idx = @file_list_scroll_offset + i
        cursor_here = idx == @cursor
        line_style = cursor_here ? @cursor_style : (row.file_row? && @selected[row.path] ? @selected_style : Lipgloss::Style.new)
        if row.file_row?
          prefix = cursor_here ? '> ' : '  '
          expand_icon = @expanded_files.include?(row.path) ? '▼ ' : '▶ '
          check = @selected[row.path] ? @pass_style.render('[x] ') : '[ ] '
          prefix + expand_icon + check + line_style.render(row.path)
        else
          prefix = cursor_here ? '    > ' : '      '
          desc = row.full_description.to_s
          prefix + line_style.render(desc)
        end
      end
      header_lines + list_lines
    end

    def build_center_panel_lines(content_h)
      return build_input_prompt_lines if @input_prompt

      case @screen
      when :indexing then build_indexing_lines
      when :running then build_running_lines(content_h)
      when :results then build_results_lines(content_h)
      else build_idle_lines
      end
    end

    def build_indexing_lines
      total = [@index_total, 1].max
      current = @index_current
      bar_width = 40
      filled = [(current.to_f / total * bar_width).round, bar_width].min
      bar = '=' * filled
      bar += '>' if current < total && filled < bar_width
      bar = bar.ljust(bar_width)
      path = @index_files[current] if current < @index_files.size
      [
        @active_title_style.render(' 3  Indexing specs '),
        '',
        "  #{current}/#{total}  [#{bar}]",
        '',
        path ? @muted_style.render("  #{path}") : '',
        '',
        @help_style.render('  q / Esc: cancel')
      ]
    end

    def build_input_prompt_lines
      [
        @active_title_style.render(' 3  Run example at line '),
        '',
        "  #{@input_prompt[:message]}#{@input_prompt[:buffer]}_",
        '',
        @help_style.render('  Enter: run  Esc: cancel')
      ]
    end

    def build_idle_lines
      title = ' 3  Output / Results '
      [
        (focused_panel == 3 ? @active_title_style.render(title) : @inactive_title_style.render(title)),
        '',
        @muted_style.render('Select files (Space), then Enter or s to run.'),
        @muted_style.render('a = run all  f = run failed (after failures)'),
        '',
        (@last_result ? "  Last: #{@last_result.summary_line}" : '')
      ].compact
    end

    def build_options_bar_lines
      labels = {
        tags_str: 'Tags', format: 'Format', out_path: 'Output',
        example_filter: 'Example', line_number: 'Line', fail_fast: 'Fail-fast', seed: 'Seed', editor: 'Editor'
      }
      max_val = 14
      segments = @options_field_keys.each_with_index.map do |key, i|
        if @options_editing == key
          val = "#{@options_edit_buffer}_"
        elsif key == :fail_fast
          val = @options[:fail_fast].to_s
        elsif key == :editor
          val = @options[:editor].to_s
        elsif %i[line_number seed].include?(key)
          val = @options[key].to_s
          val = (val.length > max_val ? "#{val[0, max_val - 2]}.." : val)
        else
          val = @options[key].to_s
          val = (val.length > max_val ? "#{val[0, max_val - 2]}.." : val)
        end
        str = "#{labels[key]}: #{val}"
        str = @cursor_style.render(str) if @options_focus && i == @options_cursor && @options_editing.nil?
        str
      end
      title = (focused_panel == 1 ? @active_title_style : @inactive_title_style).render(' 1  Options ')
      options_row = "  #{segments.join('  │  ')}"
      help = @options_editing ? '  Enter: save  Esc: cancel' : '  o: focus  ←/→: move  Enter: edit/toggle  b: unfocus  q: quit'
      help_row = @help_style.render(help)
      [title, '', options_row, help_row, '']
    end

    def build_running_lines(content_h)
      run_visible = run_output_visible_height(content_h)
      max_scroll = [@run_output.size - run_visible, 0].max
      @run_output_scroll = [@run_output_scroll, max_scroll].min
      window = @run_output[@run_output_scroll, run_visible] || []
      title = ' 3  Running RSpec '
      [
        (focused_panel == 3 ? @active_title_style.render(title) : @inactive_title_style.render(title)),
        '',
        *window.map { |l| "  #{l}" },
        '',
        @help_style.render('  j/k: scroll  PgUp/PgDn  g/G: top/bottom  2: file list  q: kill run')
      ]
    end

    def build_results_lines(content_h)
      title = ' 3  Results '
      lines = [(focused_panel == 3 ? @active_title_style.render(title) : @inactive_title_style.render(title)), '']
      @results_failed_line_indices = []
      if @last_result
        r = @last_result
        lines << "  #{r.summary_line}"
        total = r.examples.size
        pass_pct = total.positive? ? ((r.passed_count.to_f / total) * 100).round : 0
        metrics = ["Pass: #{r.passed_count}/#{total} (#{pass_pct}%)"]
        metrics << "Total: #{format_run_time(r.duration)}" if r.duration.is_a?(Numeric)
        metrics << "Seed: #{r.seed}" if r.seed
        lines << @muted_style.render("  #{metrics.join('  |  ')}")
        if r.errors_outside_of_examples.positive?
          lines << @warn_style.render("  #{r.errors_outside_of_examples} error(s) outside examples (e.g. load/hook failures)")
          if @run_output.any?
            lines << ''
            lines << @muted_style.render('  Output:')
            @run_output.each { |out_line| lines << "    #{out_line}" }
            lines << ''
          end
        end
        lines << ''
        if r.examples_with_run_time.any?
          lines << @muted_style.render('  Slowest:')
          r.slowest_examples(5).each do |ex|
            loc = [ex.file_path, ex.line_number].compact.join(':')
            lines << "    #{format_run_time(ex.run_time)}  #{loc} #{ex.description}"
          end
          lines << ''
          lines << @muted_style.render('  Fastest:')
          r.fastest_examples(5).each do |ex|
            loc = [ex.file_path, ex.line_number].compact.join(':')
            lines << "    #{format_run_time(ex.run_time)}  #{loc} #{ex.description}"
          end
          lines << ''
        end
        if r.pending_count.positive?
          lines << @muted_style.render('  Pending:')
          r.pending_examples.each do |ex|
            loc = [ex.file_path, ex.line_number].compact.join(':')
            lines << "    #{loc} #{ex.description}"
            lines << @muted_style.render("      #{ex.pending_message}") if ex.pending_message.to_s.strip != ''
          end
          lines << ''
        end
        if r.examples_with_run_time.any? && r.slowest_files(5).any?
          lines << @muted_style.render('  Slowest files:')
          r.slowest_files(5).each do |path, total_sec|
            lines << "    #{format_run_time(total_sec)}  #{path}"
          end
          lines << ''
        end
        if r.failed_count.positive?
          lines << @muted_style.render('  Failed:')
          r.failed_examples.each_with_index do |ex, i|
            @results_failed_line_indices << lines.size
            prefix = i == @results_cursor ? '> ' : '  '
            loc_path = display_path_for_result_file(ex.file_path)
            lines << @fail_style.render("#{prefix}#{loc_path}:#{ex.line_number} #{ex.description}")
            lines << @muted_style.render("    #{ex.exception_message&.lines&.first&.strip}") if ex.exception_message
          end
        end
      else
        lines << @muted_style.render('  No result data.')
      end
      lines << ''
      lines << @help_style.render('  j/k: move  PgUp/PgDn: scroll  g/G: top/bottom  e: run  O: open  b: back  r: rerun  f: failed  q: quit')
      @results_total_lines = lines.size
      max_scroll = [@results_total_lines - content_h, 0].max
      @results_scroll_offset = [[@results_scroll_offset, max_scroll].min, 0].max
      if @results_failed_line_indices.any? && @results_cursor < @results_failed_line_indices.size
        cursor_line = @results_failed_line_indices[@results_cursor]
        if cursor_line < @results_scroll_offset
          @results_scroll_offset = cursor_line
        elsif cursor_line >= @results_scroll_offset + content_h
          @results_scroll_offset = cursor_line - content_h + 1
        end
      end
      lines[@results_scroll_offset, content_h] || []
    end

    def format_run_time(seconds)
      return '' unless seconds.is_a?(Numeric)

      seconds < 1 ? "#{(seconds * 1000).round}ms" : "#{seconds.round(2)}s"
    end

    def status_line
      return ' Enter line number, Enter: run  Esc: cancel ' if @input_prompt
      return ' ↑/↓: move  PgUp/PgDn: scroll  Home/End: top/bottom  Enter: run  Esc or Ctrl+B: exit find ' if @find_buffer

      case @screen
      when :file_list
        if @options_focus
          ' 1/2/3: panels  j/k: move  Enter: edit  b: back  q: quit '
        else
          ' 1/2/3: panels  /: find  I: index  j/k: move  PgUp/PgDn  g/G: top/bottom  ]/[: expand  a: all  s: selected  e: run  O: open  f: failed  o: options  R: refresh  q: quit '
        end
      when :indexing then '  Indexing specs for search...  q / Esc: cancel '
      when :running then ' 1/2/3: panels  j/k PgUp/PgDn g/G: scroll output  2: file list  q: kill run '
      when :results then ' 1/2/3: panels  j/k: move  PgUp/PgDn: scroll  g/G: top/bottom  e: run  O: open  b: back  r: rerun  f: failed  q: quit '
      else ' 1/2/3: panels  q: quit '
      end
    end

    def truncate_plain(str, max_w)
      s = str.to_s.gsub(/\e\[[0-9;]*m/, '')
      s.length <= max_w ? s : s[0, max_w]
    end
  end
end
