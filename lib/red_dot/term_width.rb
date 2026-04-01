# frozen_string_literal: true

require 'unicode/display_width'

module RedDot
  # Terminal display width (wcwidth) for layout; ANSI SGR stripped for measurement.
  module TermWidth
    module_function

    ANSI_RE = /\e\[[0-9;]*m/

    def strip_ansi(str)
      str.to_s.gsub(ANSI_RE, '')
    end

    def of(str)
      Unicode::DisplayWidth.of(strip_ansi(str))
    end

    # Truncates to at most max_w display columns; preserves ANSI SGR sequences.
    def truncate(str, max_w)
      out = +''
      len = 0
      i = 0
      s = str.to_s
      while i < s.length
        if s[i] == "\e" && s[i + 1] == '['
          j = s.index('m', i)
          return out if j.nil?

          out << s[i..j]
          i = j + 1
          next
        end

        sub = s[i..]
        gc = sub.each_grapheme_cluster.first
        w = Unicode::DisplayWidth.of(gc)
        break if len + w > max_w

        out << gc
        len += w
        i += gc.length
      end
      out
    end
  end
end
