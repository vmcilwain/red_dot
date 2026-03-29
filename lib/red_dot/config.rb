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

      yaml_slice = {}
      yaml_slice[:format] = raw['format'] if raw.key?('format')
      yaml_slice[:out_path] = raw['output'] if raw.key?('output')
      yaml_slice[:out_path] = raw['out_path'] if raw.key?('out_path') && !raw.key?('output')
      yaml_slice[:example_filter] = raw['example_filter'] if raw.key?('example_filter')
      yaml_slice[:line_number] = raw['line_number'] if raw.key?('line_number')
      yaml_slice[:fail_fast] = raw['fail_fast'] if raw.key?('fail_fast')
      yaml_slice[:full_output] = raw['full_output'] if raw.key?('full_output')
      yaml_slice[:seed] = raw['seed'] if raw.key?('seed')
      yaml_slice[:editor] = raw['editor'] if raw.key?('editor')
      merge_overrides!(opts, yaml_slice)
    end

    # Merges CLI or normalized option hash into opts (mutates opts). Used by App and YAML scalar fields.
    # @return [Hash] opts
    def self.merge_overrides!(opts, overrides)
      return opts if overrides.nil? || overrides.empty?

      o = overrides
      if o.key?(:tags) && o[:tags].is_a?(Array)
        opts[:tags] = o[:tags].map(&:to_s).reject(&:empty?)
        opts[:tags_str] = opts[:tags].join(', ')
      end
      if o.key?(:tags_str)
        opts[:tags_str] = o[:tags_str].to_s
        opts[:tags] = parse_tags(opts[:tags_str]) unless o.key?(:tags) && o[:tags].is_a?(Array)
      end
      opts[:format] = o[:format].to_s.strip if o.key?(:format) && !o[:format].to_s.strip.empty?
      opts[:out_path] = o[:out_path].to_s if o.key?(:out_path)
      opts[:example_filter] = o[:example_filter].to_s if o.key?(:example_filter)
      opts[:line_number] = o[:line_number].to_s if o.key?(:line_number)
      opts[:fail_fast] = o[:fail_fast] ? true : false if o.key?(:fail_fast)
      opts[:full_output] = o[:full_output] ? true : false if o.key?(:full_output)
      opts[:seed] = o[:seed].to_s.strip if o.key?(:seed)
      if o.key?(:editor)
        val = o[:editor].to_s.strip.downcase
        opts[:editor] = val if VALID_EDITORS.include?(val)
      end
      opts
    end

    # @param str [String] comma/whitespace-separated tag list (from UI or CLI)
    # @return [Array<String>]
    def self.parse_tags(str)
      s = str.to_s
      return [] if s.strip.empty?

      s.split(/[\s,]+/).map(&:strip).reject(&:empty?)
    end

    def self.array_or_parse(existing, tags_val, tags_str_val)
      if tags_val.is_a?(Array)
        tags_val.map(&:to_s).reject(&:empty?)
      elsif tags_str_val.to_s.strip != ''
        parse_tags(tags_str_val)
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
