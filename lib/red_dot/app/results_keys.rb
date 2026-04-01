# frozen_string_literal: true

module RedDot
  class App
    module ResultsKeys
      private

      def handle_results_key(key)
        failed = @last_result&.failed_examples || []
        content_h = [@height - STATUS_HEIGHT - OPTIONS_BAR_HEIGHT, 5].max
        return handle_results_scroll_key(key, content_h) if @options[:full_output]

        case key
        when 'q', 'ctrl+c' then [self, Bubbletea.quit]
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
        when 'e' then run_results_example(failed)
        when 'O' then open_results_example(failed)
        when 'r' then run_specs(@last_run_paths || @discovery.default_run_all_paths)
        when 'f'
          return run_specs(@run_failed_paths) if @run_failed_paths&.any?

          [self, nil]
        else [self, nil]
        end
      end

      def handle_results_scroll_key(key, content_h)
        max_scroll = [@results_total_lines - content_h, 0].max
        case key
        when 'up', 'k' then @results_scroll_offset = [@results_scroll_offset - 1, 0].max
        when 'down', 'j' then @results_scroll_offset = [@results_scroll_offset + 1, max_scroll].min
        when 'pgup', 'ctrl+u' then @results_scroll_offset = [@results_scroll_offset - content_h, 0].max
        when 'pgdown', 'ctrl+d' then @results_scroll_offset = [@results_scroll_offset + content_h, max_scroll].min
        when 'home', 'g' then @results_scroll_offset = 0
        when 'end', 'G' then @results_scroll_offset = max_scroll
        else return handle_results_key_without_scroll(key)
        end
        [self, nil]
      end

      def handle_results_key_without_scroll(key)
        @options[:full_output] = false
        result = handle_results_key(key)
        @options[:full_output] = true
        result
      end

      def run_results_example(failed)
        ex = failed[@results_cursor]
        if ex&.line_number
          display_path = ResultPaths.display_path_for_result_file(ex.file_path, @last_run_component_root)
          return run_specs(["#{display_path}:#{ex.line_number}"])
        end
        [self, nil]
      end

      def open_results_example(failed)
        ex = failed[@results_cursor]
        if ex
          display_path = ResultPaths.display_path_for_result_file(ex.file_path, @last_run_component_root)
          EditorLauncher.open(path: display_path, line: ex.line_number, working_dir: @working_dir, editor: @options[:editor])
        end
        [self, nil]
      end
    end
  end
end
