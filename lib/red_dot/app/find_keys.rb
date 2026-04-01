# frozen_string_literal: true

module RedDot
  class App
    module FindKeys
      private

      def handle_find_key(message)
        list = display_rows
        return handle_find_backspace(list) if message.respond_to?(:backspace?) && message.backspace?
        return handle_find_enter(list) if message.respond_to?(:enter?) && message.enter?

        key = message.to_s
        if (message.respond_to?(:esc?) && message.esc?) || key == 'ctrl+b'
          sync_cursor_to_full_list
          @expanded_files.clear
          @find_buffer = nil
          return [self, nil]
        end
        return handle_find_nav(key, list) if %w[up down pgup ctrl+u pgdown ctrl+d home end].include?(key)

        if key == 'ctrl+t'
          row = list[@cursor]
          toggle_row_selection(row) if row
          return [self, nil]
        end
        handle_find_char(message, key)
      end

      def handle_find_backspace(list)
        @find_buffer = @find_buffer[0, [@find_buffer.length - 1, 0].max]
        @cursor = [@cursor, list.size - 1].min
        @cursor = 0 if list.size.positive? && @cursor.negative?
        [self, nil]
      end

      def handle_find_enter(list)
        row = list[@cursor]
        return run_specs([row.runnable_path]) if row

        [self, nil]
      end

      def handle_find_nav(key, list)
        content_h = [@height - STATUS_HEIGHT - OPTIONS_BAR_HEIGHT, 5].max
        visible_list_height = file_list_visible_height(content_h)
        max_scroll = [list.size - visible_list_height, 0].max
        case key
        when 'up'
          @cursor = [[@cursor - 1, 0].max, [list.size - 1, 0].max].min
        when 'down'
          @cursor = [[@cursor + 1, [list.size - 1, 0].max].min, 0].max
        when 'pgup', 'ctrl+u'
          @cursor = [@cursor - visible_list_height, 0].max
          @file_list_scroll_offset = [@file_list_scroll_offset - visible_list_height, 0].max
        when 'pgdown', 'ctrl+d'
          @cursor = [@cursor + visible_list_height, [list.size - 1, 0].max].min
          @file_list_scroll_offset = [@file_list_scroll_offset + visible_list_height, max_scroll].min
        when 'home'
          @cursor = 0
          @file_list_scroll_offset = 0
        when 'end'
          @cursor = [list.size - 1, 0].max
          @file_list_scroll_offset = max_scroll
        end
        [self, nil]
      end

      def handle_find_char(message, key)
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
        end
        [self, nil]
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
    end
  end
end
