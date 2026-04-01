# frozen_string_literal: true

module RedDot
  class App
    module StatusView
      private

      def status_line
        return ' Enter line number, Enter: run  Esc: cancel ' if @input_prompt
        return find_status_line if @find_buffer

        case @screen
        when :file_list then @options_focus ? options_status_line : file_list_status_line
        when :indexing then '  Indexing specs for search...  q / Esc: cancel '
        when :running then ' 1/2/3: panels  j/k PgUp/PgDn g/G: scroll output  2: file list  q: kill run '
        when :results then results_status_line
        else ' 1/2/3: panels  q: quit '
        end
      end

      def find_status_line
        ' ↑/↓: move  PgUp/PgDn: scroll  Home/End: top/bottom  Ctrl+T: toggle  Enter: run  Esc or Ctrl+B: exit find '
      end

      def options_status_line
        ' 1/2/3: panels  j/k: move  Enter: edit  R: refresh  b: back  q: quit '
      end

      def file_list_status_line
        ' 1/2/3: panels  /: find  I: index  j/k: move  PgUp/PgDn  g/G: top/bottom  ]/[: expand  ' \
          'Ctrl+T: select  a: all  s: selected  e: run  O: open  f: failed  o: options  R: refresh  q: quit '
      end

      def results_status_line
        move_or_scroll = @options[:full_output] ? 'scroll' : 'move'
        " 1/2/3: panels  j/k: #{move_or_scroll}  PgUp/PgDn: scroll  g/G: top/bottom  e: run  O: open  b: back  " \
          'r: rerun  f: failed  q: quit '
      end
    end
  end
end
