# frozen_string_literal: true

module RedDot
  class App
    module FileListKeys # rubocop:disable Metrics/ModuleLength -- single handler method
      private

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
          handle_file_list_expand(row)
        when 'left'
          handle_file_list_collapse(list, row)
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
        when 'ctrl+t'
          toggle_row_selection(row) if row
          [self, nil]
        when 'alt+u', 'ctrl+w'
          clear_selection
          [self, nil]
        when 'enter', 's' then run_specs(paths_for_run)
        when 'a' then run_specs(flat_spec_list.empty? ? @discovery.default_run_all_paths : flat_spec_list)
        when 'f'
          return run_specs(@run_failed_paths) if @run_failed_paths&.any?

          [self, nil]
        when 'e'
          handle_file_list_run_example(row)
        when 'O'
          handle_file_list_open(row)
        when 'o'
          @options_focus = true
          [self, nil]
        when 'R'
          refresh_spec_list
          [self, nil]
        when 'I', 'i' then start_background_index(force: key == 'I')
        when '?'
          @help_visible = true
          [self, nil]
        else [self, nil]
        end
      end

      def handle_file_list_expand(row)
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
      end

      def handle_file_list_collapse(list, row)
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
      end

      def handle_file_list_run_example(row)
        if row&.example_row?
          run_specs([row.runnable_path])
        elsif row&.file_row?
          @input_prompt = { message: 'Line number (e.g. 42): ', buffer: '', file: row.path }
        end
        [self, nil]
      end

      def handle_file_list_open(row)
        if row
          EditorLauncher.open(
            path: row.path,
            line: row.example_row? ? row.line_number : nil,
            working_dir: @working_dir,
            editor: @options[:editor]
          )
        end
        [self, nil]
      end
    end
  end
end
