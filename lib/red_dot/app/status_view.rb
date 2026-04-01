# frozen_string_literal: true

module RedDot
  class App
    module StatusView
      private

      def status_line
        return '' if @input_prompt || @help_visible
        return find_status_line if @find_buffer

        case @screen
        when :file_list then @options_focus ? options_status_line : file_list_status_line
        when :indexing then ' Indexing...  q: cancel'
        when :running then ' j/k: scroll  q: kill  2: files  Tab: panels'
        when :results then results_status_line
        else ' q: quit  ?: help'
        end
      end

      def find_status_line
        ' ↑/↓: move  Ctrl+T: toggle  Enter: run  Esc: exit'
      end

      def options_status_line
        ' ←/→: move  Enter: edit  b: back  q: quit'
      end

      def file_list_status_line
        ' /: find  I: index  Ctrl+T: select  a: all  s: run  e: example  o: opts  ?: help  q: quit'
      end

      def results_status_line
        ' e: run  O: open  r: rerun  f: failed  b: back  ?: help  q: quit'
      end
    end
  end
end
