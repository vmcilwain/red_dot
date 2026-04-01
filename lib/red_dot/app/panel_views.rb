# frozen_string_literal: true

module RedDot
  class App
    module PanelViews
      private

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
        bar = "#{'=' * filled}#{'>' if current < total && filled < bar_width}".ljust(bar_width)
        path = @index_files[current] if current < @index_files.size
        [
          @active_title_style.render(' 3  Indexing specs '), '',
          "  #{current}/#{total}  [#{bar}]", '',
          path ? @muted_style.render("  #{path}") : '', '',
          @help_style.render('  q / Esc: cancel')
        ]
      end

      def build_input_prompt_lines
        [
          @active_title_style.render(' 3  Run example at line '), '',
          "  #{@input_prompt[:message]}#{@input_prompt[:buffer]}_", '',
          @help_style.render('  Enter: run  Esc: cancel')
        ]
      end

      def build_idle_lines
        title = ' 3  Output / Results '
        [
          (focused_panel == 3 ? @active_title_style.render(title) : @inactive_title_style.render(title)), '',
          @muted_style.render('Select files or examples (Ctrl+T), then Enter or s to run.'),
          @muted_style.render('a = run all  f = run failed (after failures)'), '',
          (@last_result ? "  Last: #{@last_result.summary_line}" : '')
        ].compact
      end

      def build_options_bar_lines
        segments = @options_field_keys.each_with_index.map { |key, i| render_option_segment(key, i) }
        title = (focused_panel == 1 ? @active_title_style : @inactive_title_style).render(' 1  Options ')
        help = if @options_editing
                 '  Enter: save  Esc: cancel'
               else
                 '  o: focus  ←/→: move  Enter: edit/toggle  b: unfocus  q: quit'
               end
        [title, '', "  #{segments.join('  │  ')}", @help_style.render(help), '']
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
        title = ' 3  Running RSpec '
        [
          (focused_panel == 3 ? @active_title_style.render(title) : @inactive_title_style.render(title)), '',
          *window.map { |l| "  #{l}" }, '',
          @help_style.render('  j/k: scroll  PgUp/PgDn  g/G: top/bottom  2: file list  q: kill run')
        ]
      end

      def format_run_time(seconds)
        return '' unless seconds.is_a?(Numeric)

        seconds < 1 ? "#{(seconds * 1000).round}ms" : "#{seconds.round(2)}s"
      end
    end
  end
end
