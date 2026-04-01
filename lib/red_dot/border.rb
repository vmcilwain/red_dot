# frozen_string_literal: true

require 'lipgloss'

require_relative 'term_width'

module RedDot
  module Border
    TL = '╭'
    TR = '╮'
    BL = '╰'
    BR = '╯'
    H  = '─'
    V  = '│'

    module_function

    def render(width:, height:, title: '', lines: [], active: false, active_style: nil, inactive_style: nil)
      border_style = active ? active_style : inactive_style
      inner_w = [width - 2, 0].max
      inner_h = [height - 2, 0].max

      top = build_top(inner_w, title, border_style)
      bottom = border_style ? border_style.render("#{BL}#{H * inner_w}#{BR}") : "#{BL}#{H * inner_w}#{BR}"

      padded = pad_content(lines, inner_w, inner_h)
      v_left  = border_style ? border_style.render(V) : V
      v_right = border_style ? border_style.render(V) : V

      body = padded.map { |line| "#{v_left}#{fit_line(line, inner_w)}#{v_right}" }

      [top, *body, bottom].first(height).join("\n")
    end

    def build_top(inner_w, title, style)
      if title.empty?
        line = "#{TL}#{H * inner_w}#{TR}"
        return style ? style.render(line) : line
      end

      label = " #{title} "
      label_visible_len = TermWidth.of(label)
      remaining = [inner_w - label_visible_len, 0].max
      line_chars = "#{TL}#{H}#{label}#{H * [remaining - 1, 0].max}#{TR}"

      return line_chars unless style

      plain_label = " #{strip_ansi(title)} "
      border_only = "#{TL}#{H}#{' ' * plain_label.length}#{H * [remaining - 1, 0].max}#{TR}"
      styled_border = style.render(border_only)
      placeholder = ' ' * plain_label.length
      styled_border.sub(placeholder, label)
    end

    def pad_content(lines, inner_w, inner_h)
      result = lines.first(inner_h).map { |l| fit_line(l, inner_w) }
      padding = [inner_h - result.size, 0].max
      result + Array.new(padding) { ' ' * inner_w }
    end

    def fit_line(line, width)
      vlen = TermWidth.of(line)
      if vlen > width
        TermWidth.truncate(line, width)
      elsif vlen < width
        "#{line}#{' ' * (width - vlen)}"
      else
        line
      end
    end

    def strip_ansi(str)
      TermWidth.strip_ansi(str)
    end
  end
end
