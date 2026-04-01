# frozen_string_literal: true

module RedDot
  class App
    module KeyHandlers
      private

      def handle_key(message)
        return handle_input_prompt_key(message) if @input_prompt

        key = message.to_s

        if @help_visible
          @help_visible = false
          return [self, nil]
        end

        if @screen == :running && @run_pid && ['q', 'ctrl+c'].include?(key)
          kill_run
          @screen = :file_list
          return [self, nil]
        end
        return handle_find_key(message) if @find_buffer && @screen == :file_list

        unless @options_editing
          case key
          when '1', '2', '0'
            apply_panel_focus_digit(key.to_i)
            return [self, nil]
          when 'tab'
            cycle_panel_focus(:forward)
            return [self, nil]
          when 'shift+tab'
            cycle_panel_focus(:backward)
            return [self, nil]
          when '?'
            @help_visible = true
            return [self, nil]
          end
        end
        return handle_options_key(key, message) if @options_focus

        case @screen
        when :file_list then handle_file_list_key(key, message)
        when :indexing
          if ['q', 'ctrl+c', 'esc'].include?(key)
            @index_thread&.kill
            @index_thread = nil
            @screen = :file_list
          end
          [self, nil]
        when :running then handle_running_key(key)
        when :results then handle_results_key(key)
        else [self, nil]
        end
      end

      def cycle_panel_focus(direction)
        available = [2]
        available << 0 if @run_pid || @last_result
        available << 1

        current = focused_panel
        idx = available.index(current) || 0
        next_idx = direction == :forward ? (idx + 1) % available.size : (idx - 1) % available.size
        apply_panel_focus_digit(available[next_idx])
      end

      def handle_mouse(message)
        return [self, nil] unless message.wheel?

        content_h = [@height - STATUS_HEIGHT - OPTIONS_BAR_HEIGHT, 5].max
        left_w, = main_panel_widths
        in_spec_list = message.x < left_w && message.y >= OPTIONS_BAR_HEIGHT && message.y < @height - STATUS_HEIGHT
        return [self, nil] unless in_spec_list

        list = display_rows
        visible_list_height = file_list_visible_height(content_h)
        max_scroll = [list.size - visible_list_height, 0].max
        return [self, nil] if max_scroll <= 0

        case message.button
        when Bubbletea::MouseMessage::BUTTON_WHEEL_UP
          @cursor = [[@cursor - 1, 0].max, list.size - 1].min
          @file_list_scroll_offset = [@file_list_scroll_offset - 1, 0].max
          @file_list_scroll_offset = @cursor if @cursor < @file_list_scroll_offset
        when Bubbletea::MouseMessage::BUTTON_WHEEL_DOWN
          @cursor = [[@cursor + 1, list.size - 1].min, 0].max
          @file_list_scroll_offset = [@file_list_scroll_offset + 1, max_scroll].min
          if @cursor >= @file_list_scroll_offset + visible_list_height
            @file_list_scroll_offset = @cursor - visible_list_height + 1
          end
        end
        [self, nil]
      end
    end
  end
end
