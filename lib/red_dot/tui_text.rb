# frozen_string_literal: true

module RedDot
  # ANSI-aware width, truncation, and block padding for TUI layout.
  module TuiText
    def visible_length(str)
      str.to_s.gsub(/\e\[[0-9;]*m/, '').length
    end

    def truncate_line(str, max_w)
      return str.to_s if visible_length(str) <= max_w

      out = +''
      len = 0
      i = 0
      s = str.to_s
      while i < s.length
        if s[i] == "\e" && s[i + 1] == '['
          j = s.index('m', i)
          i = j ? j + 1 : s.length
        else
          break if len >= max_w

          len += 1
          out << s[i]
          i += 1
        end
      end
      out
    end

    def pad_line(str, width)
      str.to_s + (' ' * [width - visible_length(str), 0].max)
    end

    def block_to_size(lines, width, height)
      truncated = lines.first(height).map { |line| pad_line(truncate_line(line, width), width) }
      padding = [height - truncated.size, 0].max
      (truncated + Array.new(padding) { ' ' * width }).join("\n")
    end

    def truncate_plain(str, max_w)
      s = str.to_s.gsub(/\e\[[0-9;]*m/, '')
      s.length <= max_w ? s : s[0, max_w]
    end
  end
end
