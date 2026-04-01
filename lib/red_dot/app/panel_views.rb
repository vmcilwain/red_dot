# frozen_string_literal: true

module RedDot
  class App
    module PanelViews
      private

      def build_center_panel_lines(content_h)
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
        bar = "#{'=' * filled}#{'>' if current < total && filled < bar_width}".ljust(bar_width)
        path = @index_files[current] if current < @index_files.size
        [
          " #{current}/#{total}  [#{bar}]", '',
          path ? @muted_style.render(" #{path}") : '', '',
          @help_style.render(' q/Esc: cancel')
        ]
      end

      def build_idle_lines
        lines = []
        lines << @muted_style.render(' Ctrl+T to select, Enter/s to run.')
        lines << @muted_style.render(' a: all  f: failed')
        lines << ''
        lines << " Last: #{@last_result.summary_line}" if @last_result
        lines
      end

      def build_options_bar_content
        segments = @options_field_keys.each_with_index.map { |key, i| render_option_segment(key, i) }
        [" #{segments.join('  │  ')}"]
      end

      def render_option_segment(key, idx)
        labels = { tags_str: 'Tags', format: 'Format', out_path: 'Output', example_filter: 'Example',
                   line_number: 'Line', fail_fast: 'Fail-fast', full_output: 'Full output', seed: 'Seed',
                   editor: 'Editor' }
        val = option_display_value(key)
        str = "#{labels[key]}: #{val}"
        str = @cursor_style.render(str) if @options_focus && idx == @options_cursor && @options_editing.nil?
        str
      end

      def option_display_value(key)
        return "#{@options_edit_buffer}_" if @options_editing == key
        return @options[key].to_s if %i[fail_fast full_output editor].include?(key)

        val = @options[key].to_s
        val.length > 14 ? "#{val[0, 12]}.." : val
      end

      def build_running_lines(content_h)
        run_visible = run_output_visible_height(content_h)
        max_scroll = [@run_output.size - run_visible, 0].max
        @run_output_scroll = [@run_output_scroll, max_scroll].min
        window = @run_output[@run_output_scroll, run_visible] || []
        window.map { |l| " #{l}" }
      end

      def format_run_time(seconds)
        return '' unless seconds.is_a?(Numeric)

        seconds < 1 ? "#{(seconds * 1000).round}ms" : "#{seconds.round(2)}s"
      end
    end
  end
end
