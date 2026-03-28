# frozen_string_literal: true

require 'yaml'

module RedDot
  # Loads and merges options from user and project config.
  class Config
    VALID_EDITORS = %w[vscode cursor textmate].freeze

    DEFAULT_OPTIONS = {
      tags: [],
      tags_str: '',
      format: 'progress',
      out_path: '',
      example_filter: '',
      line_number: '',
      fail_fast: false,
      full_output: false,
      seed: '',
      editor: 'cursor'
    }.freeze

    # @return [String] XDG/config or ~/.config/red_dot/config.yml
    def self.user_config_path
      base = ENV.fetch('XDG_CONFIG_HOME', File.join(Dir.home, '.config'))
      File.join(base, 'red_dot', 'config.yml')
    end

    # @return [String] working_dir/.red_dot.yml
    def self.project_config_path(working_dir)
      File.join(File.expand_path(working_dir), '.red_dot.yml')
    end

    # Merges user + project config. @return [Hash] options (tags, format, out_path, etc.)
    def self.load(working_dir: Dir.pwd)
      opts = DEFAULT_OPTIONS.dup
      project_path = project_config_path(working_dir)
      if File.readable?(project_path)
        opts = merge_file(opts, user_config_path)
        opts = merge_file(opts, project_path)
      end
      opts
    end

    # Merges YAML at path into opts. @return [Hash]
    def self.merge_file(opts, path)
      return opts unless path && File.readable?(path)

      raw = YAML.safe_load_file(path, permitted_classes: [Symbol])
      return opts unless raw.is_a?(Hash)

      opts = opts.dup
      opts[:tags] = array_or_parse(opts[:tags], raw['tags'], raw['tags_str'])
      opts[:tags_str] = raw['tags_str'].to_s.strip if raw.key?('tags_str')
      opts[:tags_str] = (raw['tags'] || []).join(', ') if raw.key?('tags') && raw['tags'].is_a?(Array)
      opts[:format] = raw['format'].to_s.strip if raw.key?('format') && !raw['format'].to_s.strip.empty?
      opts[:out_path] = raw['output'].to_s if raw.key?('output')
      opts[:out_path] = raw['out_path'].to_s if raw.key?('out_path') && !raw.key?('output')
      opts[:example_filter] = raw['example_filter'].to_s if raw.key?('example_filter')
      opts[:line_number] = raw['line_number'].to_s if raw.key?('line_number')
      opts[:fail_fast] = raw['fail_fast'] ? true : false if raw.key?('fail_fast')
      opts[:full_output] = raw['full_output'] ? true : false if raw.key?('full_output')
      opts[:seed] = raw['seed'].to_s.strip if raw.key?('seed')
      if raw.key?('editor')
        val = raw['editor'].to_s.strip.downcase
        opts[:editor] = val if VALID_EDITORS.include?(val)
      end
      opts
    end

    def self.array_or_parse(existing, tags_val, tags_str_val)
      if tags_val.is_a?(Array)
        tags_val.map(&:to_s).reject(&:empty?)
      elsif tags_str_val.to_s.strip != ''
        tags_str_val.to_s.split(/[\s,]+/).map(&:strip).reject(&:empty?)
      else
        existing
      end
    end

    # @return [Array<String>, nil] component root dirs from .red_dot.yml, or nil
    def self.component_roots(working_dir: Dir.pwd)
      path = project_config_path(working_dir)
      return nil unless File.readable?(path)

      raw = YAML.safe_load_file(path, permitted_classes: [Symbol])
      return nil unless raw.is_a?(Hash) && raw.key?('components')
      return nil unless raw['components'].is_a?(Array)

      raw['components'].map(&:to_s).reject(&:empty?)
    end
  end
end
