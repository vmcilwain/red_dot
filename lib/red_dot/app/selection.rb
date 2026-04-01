# frozen_string_literal: true

module RedDot
  class App
    module Selection
      private

      def paths_for_run
        selected = @selected.select { |_, v| v }.keys
        if selected.any?
          expand_selected_paths_for_run(selected)
        else
          row = display_rows[@cursor]
          row ? [row.runnable_path] : @discovery.default_run_all_paths
        end
      end

      def expand_selected_paths_for_run(keys)
        file_paths = []
        line_paths = []
        keys.each do |k|
          if k.match?(/\A(.+):(\d+)\z/)
            line_paths << k
          else
            file_paths << k
          end
        end
        file_set = file_paths.to_h { |p| [p, true] }
        line_paths = line_paths.reject do |lp|
          m = lp.match(/\A(.+):(\d+)\z/)
          m && file_set[m[1]]
        end
        (file_paths + line_paths).sort
      end

      def purge_example_selections_for_file(path)
        stale = @selected.keys.select do |k|
          k != path && k.match?(/\A#{Regexp.escape(path)}:\d+\z/)
        end
        stale.each { |k| @selected.delete(k) }
      end

      def toggle_row_selection(row)
        if row.file_row?
          path = row.path
          new_val = !@selected[path]
          purge_example_selections_for_file(path)
          @selected[path] = new_val
        else
          rid = row.row_id
          path = row.path
          new_val = !@selected[rid]
          if new_val
            @selected[path] = false if @selected[path]
            @selected[rid] = true
          else
            @selected[rid] = false
          end
        end
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

      def clear_selection
        @selected.clear
      end
    end
  end
end
