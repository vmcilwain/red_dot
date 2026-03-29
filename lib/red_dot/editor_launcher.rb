# frozen_string_literal: true

require_relative 'config'

module RedDot
  # Opens a path in the configured editor (vscode, cursor, textmate).
  class EditorLauncher
    def self.open(path:, working_dir:, editor:, line: nil)
      return if path.to_s.strip.empty?

      full_path = File.expand_path(path, working_dir)
      return unless File.exist?(full_path)

      ed = (editor || 'cursor').to_s.downcase
      ed = 'cursor' unless Config::VALID_EDITORS.include?(ed)

      args = case ed
             when 'vscode'
               line ? ['code', '-g', "#{full_path}:#{line}"] : ['code', full_path]
             when 'cursor'
               line ? ['cursor', '-g', "#{full_path}:#{line}"] : ['cursor', full_path]
             when 'textmate'
               line ? ['mate', '-l', line.to_s, full_path] : ['mate', full_path]
             else
               ['cursor', full_path]
             end

      pid = Process.spawn(*args, out: File::NULL, err: File::NULL)
      Process.detach(pid)
    end
  end
end
