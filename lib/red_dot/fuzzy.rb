# frozen_string_literal: true

module RedDot
  # Subsequence fuzzy match for find/filter (paths and example descriptions).
  module FuzzySearch
    def fuzzy_match(paths, query)
      return paths if query.to_s.strip.empty?

      q = query.to_s.downcase
      paths.select { |path| fuzzy_match_string?(path, q) }
    end

    def fuzzy_match_string?(str, query)
      return true if query.to_s.strip.empty?

      q = query.to_s.downcase
      s = str.to_s.downcase
      j = 0
      s.each_char do |c|
        j += 1 if j < q.length && c == q[j]
      end
      j == q.length
    end
  end
end
