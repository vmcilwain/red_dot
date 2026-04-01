# frozen_string_literal: true

require_relative 'term_width'

module RedDot
  module Modal
    module_function

    def overlay(base_lines, modal_lines, screen_width, screen_height, modal_width, modal_height)
      rows = base_lines.is_a?(String) ? base_lines.split("\n") : base_lines.dup
      rows = rows.first(screen_height)
      rows += Array.new([screen_height - rows.size, 0].max) { ' ' * screen_width }

      start_row = [((screen_height - modal_height) / 2), 0].max
      start_col = [((screen_width - modal_width) / 2), 0].max

      m_lines = modal_lines.is_a?(String) ? modal_lines.split("\n") : modal_lines
      m_lines.each_with_index do |mline, i|
        row_idx = start_row + i
        break if row_idx >= screen_height

        rows[row_idx] = splice_line(rows[row_idx] || '', mline, start_col, screen_width)
      end

      rows.join("\n")
    end

    def splice_line(base, overlay_str, col, max_width)
      base_plain = expand_to_plain(base, max_width)
      over_plain_len = TermWidth.of(overlay_str)

      before = base_plain[0, col] || ''
      after_start = col + over_plain_len
      after = after_start < base_plain.length ? base_plain[after_start..] : ''

      result = "#{before}#{overlay_str}#{after}"
      Border.fit_line(result, max_width)
    end

    def expand_to_plain(str, width)
      plain = TermWidth.strip_ansi(str)
      w = TermWidth.of(plain)
      w < width ? plain + (' ' * (width - w)) : TermWidth.truncate(plain, width)
    end
  end
end
