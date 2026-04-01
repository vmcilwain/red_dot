# frozen_string_literal: true

require_relative 'term_width'

module RedDot
  # ANSI-aware width, truncation, and block padding for TUI layout (display width).
  module TuiText
    def visible_length(str)
      TermWidth.of(str)
    end

    def truncate_line(str, max_w)
      return str.to_s if TermWidth.of(str) <= max_w

      TermWidth.truncate(str, max_w)
    end

    def pad_line(str, width)
      str.to_s + (' ' * [width - TermWidth.of(str), 0].max)
    end

    def block_to_size(lines, width, height)
      truncated = lines.first(height).map { |line| pad_line(truncate_line(line, width), width) }
      padding = [height - truncated.size, 0].max
      (truncated + Array.new(padding) { ' ' * width }).join("\n")
    end

    def truncate_plain(str, max_w)
      s = str.to_s.gsub(/\e\[[0-9;]*m/, '')
      return s if TermWidth.of(s) <= max_w

      TermWidth.truncate(s, max_w)
    end
  end
end
