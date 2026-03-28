# frozen_string_literal: true

module RedDot
  # Parses argv into working_dir and option_overrides (format, tags, out_path, example_filter, line_number, fail_fast).
  class Cli
    # @return [Hash] { working_dir:, option_overrides: }
    def self.parse(argv = ARGV)
      args = argv.dup
      overrides = {}
      dir = nil
      i = 0
      while i < args.size
        arg = args[i]
        case arg
        when '--format', '-f'
          overrides[:format] = args[i + 1] if args[i + 1] && !args[i + 1].start_with?('-')
          i += 2
        when '--tag', '-t'
          (overrides[:tags] ||= []) << args[i + 1] if args[i + 1] && !args[i + 1].start_with?('-')
          i += 2
        when '--out', '-o'
          overrides[:out_path] = args[i + 1] if args[i + 1]
          i += 2
        when '--example', '-e'
          overrides[:example_filter] = args[i + 1] if args[i + 1]
          i += 2
        when '--line', '-l'
          overrides[:line_number] = args[i + 1] if args[i + 1] && !args[i + 1].start_with?('-')
          i += 2
        when '--fail-fast'
          overrides[:fail_fast] = true
          i += 1
        when /^[^-]/
          dir = arg
          i += 1
        else
          i += 1
        end
      end
      { working_dir: dir || Dir.pwd, option_overrides: overrides }
    end
  end
end
