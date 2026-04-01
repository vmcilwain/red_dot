# frozen_string_literal: true

module RedDot
  class App
    module OptionsKeys
      private

      def handle_options_key(key, message)
        return handle_options_edit_key(key, message) if @options_editing

        case key
        when 'q', 'ctrl+c' then [self, Bubbletea.quit]
        when 'R'
          refresh_spec_list
          [self, nil]
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
          apply_options_field_toggle
          [self, nil]
        else [self, nil]
        end
      end

      def apply_options_field_toggle
        field = @options_field_keys[@options_cursor]
        case field
        when :fail_fast then @options[:fail_fast] = !@options[:fail_fast]
        when :full_output then @options[:full_output] = !@options[:full_output]
        when :editor
          idx = RedDot::Config::VALID_EDITORS.index(@options[:editor].to_s) || 0
          @options[:editor] = RedDot::Config::VALID_EDITORS[(idx + 1) % RedDot::Config::VALID_EDITORS.size]
        else
          @options_editing = field
          @options_edit_buffer = @options[field].to_s.dup
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
          @options[:tags] = Config.parse_tags(@options[:tags_str]) if field == :tags_str
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

      def handle_running_key(key)
        content_h = [@height - STATUS_HEIGHT - OPTIONS_BAR_HEIGHT, 5].max
        run_visible = run_output_visible_height(content_h)
        max_scroll = [@run_output.size - run_visible, 0].max
        case key
        when 'q', 'ctrl+c'
          kill_run
          @screen = :file_list
        when '2' then @screen = :file_list
        when 'up', 'k' then @run_output_scroll = [@run_output_scroll - 1, 0].max
        when 'down', 'j' then @run_output_scroll = [@run_output_scroll + 1, max_scroll].min
        when 'pgup', 'ctrl+u' then @run_output_scroll = [@run_output_scroll - run_visible, 0].max
        when 'pgdown', 'ctrl+d' then @run_output_scroll = [@run_output_scroll + run_visible, max_scroll].min
        when 'home', 'g' then @run_output_scroll = 0
        when 'end', 'G' then @run_output_scroll = max_scroll
        end
        [self, nil]
      end
    end
  end
end
