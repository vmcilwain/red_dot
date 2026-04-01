# frozen_string_literal: true

module RedDot
  class App
    module FileListView
      private

      def index_stale_hint_line
        return nil if @index_thread&.alive?

        paths = flat_spec_list
        return nil if paths.empty?

        stale = ExampleDiscovery.stale_paths(@discovery, paths)
        return nil if stale.empty?

        if stale.size == paths.size
          '  No index yet — press I to index for test name search.'
        else
          noun = stale.size == 1 ? 'file' : 'files'
          "  Index incomplete — press I to refresh search index (#{stale.size} spec #{noun} out of date)."
        end
      end

      def build_file_list_lines(content_h)
        header_lines = build_file_list_header
        list = display_rows
        return header_lines << empty_file_list_line if list.empty?

        @cursor = [@cursor, list.size - 1].min
        visible_list_height = [content_h - header_lines.size, 1].max
        max_scroll = [list.size - visible_list_height, 0].max
        adjust_file_list_scroll(visible_list_height, max_scroll)
        visible_rows = list[@file_list_scroll_offset, visible_list_height] || []
        header_lines + visible_rows.each_with_index.map { |row, i| render_file_list_row(row, @file_list_scroll_offset + i) }
      end

      def build_file_list_header
        lines = []
        lines << @muted_style.render(" Find: #{@find_buffer}_") if @find_buffer
        hint = index_stale_hint_line
        lines << @muted_style.render(hint) if hint
        lines
      end

      def empty_file_list_line
        if @find_buffer.to_s.strip.empty?
          @muted_style.render("  #{@discovery.empty_state_message}")
        else
          @muted_style.render('  No matches')
        end
      end

      def adjust_file_list_scroll(visible_list_height, max_scroll)
        @file_list_scroll_offset = [[@file_list_scroll_offset, max_scroll].min, 0].max
        @file_list_scroll_offset = @cursor if @cursor < @file_list_scroll_offset
        return unless @cursor >= @file_list_scroll_offset + visible_list_height

        @file_list_scroll_offset = @cursor - visible_list_height + 1
      end

      def render_file_list_row(row, idx)
        cursor_here = idx == @cursor
        selected_row = row.file_row? ? @selected[row.path] : @selected[row.row_id]
        if row.file_row?
          expand_icon = @expanded_files.include?(row.path) ? '▼ ' : '▶ '
          text = " #{expand_icon}#{row.path}"
        else
          text = "   #{row.full_description}"
        end
        if cursor_here
          @cursor_style.render(text)
        elsif selected_row
          @selected_line_style.render(text)
        else
          text
        end
      end
    end
  end
end
