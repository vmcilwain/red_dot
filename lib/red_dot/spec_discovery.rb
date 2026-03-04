# frozen_string_literal: true

require 'pathname'

module RedDot
  class SpecDiscovery
    DEFAULT_SPEC_DIR = 'spec'
    DEFAULT_PATTERN = '**/*_spec.rb'
    COMPONENTS_DIR = 'components'

    def initialize(working_dir: Dir.pwd)
      @working_dir = File.expand_path(working_dir)
    end

    def umbrella?
      components_dir = File.join(@working_dir, COMPONENTS_DIR)
      File.directory?(components_dir)
    end

    def component_roots
      return [] unless umbrella?

      explicit = Config.component_roots(working_dir: @working_dir)
      return explicit.map { |r| r == '.' ? '' : r } if explicit&.any?

      roots = []
      root_spec_dir = spec_dir_for_root
      roots << '' if root_spec_dir && Dir.exist?(File.join(@working_dir, root_spec_dir))

      comp_dir = File.join(@working_dir, COMPONENTS_DIR)
      return roots unless Dir.exist?(comp_dir)

      Dir.children(comp_dir).each do |name|
        next unless File.directory?(File.join(comp_dir, name))

        comp_path = "#{COMPONENTS_DIR}/#{name}"
        comp_spec = File.join(@working_dir, comp_path, DEFAULT_SPEC_DIR)
        roots << comp_path if Dir.exist?(comp_spec)
      end
      roots.sort
    end

    def spec_dir
      if umbrella?
        return File.join(@working_dir, DEFAULT_SPEC_DIR) if component_roots.empty?

        first = component_roots.first
        base = first.empty? ? @working_dir : File.join(@working_dir, first)
        spec_subdir = read_default_path_from_rspec(base) || DEFAULT_SPEC_DIR
        return File.join(base, spec_subdir)
      end

      path = read_default_path_from_rspec(@working_dir)
      base = path || DEFAULT_SPEC_DIR
      File.join(@working_dir, base)
    end

    def relative_spec_path
      read_default_path_from_rspec(@working_dir) || DEFAULT_SPEC_DIR
    end

    def discover
      if umbrella?
        discover_umbrella
      else
        discover_single
      end
    end

    def discover_grouped_by_dir
      files = discover
      files.group_by { |f| File.dirname(f) }.transform_values(&:sort)
    end

    def run_context_for(display_path)
      if umbrella?
        run_context_umbrella(display_path)
      else
        { run_cwd: @working_dir, rspec_path: display_path }
      end
    end

    def default_run_all_paths
      if umbrella?
        flat_spec_list_for_umbrella
      else
        [relative_spec_path]
      end
    end

    def empty_state_message
      if umbrella? && component_roots.empty?
        "No spec directory or components with spec/ found in #{@working_dir}"
      else
        "No spec files in #{spec_dir}"
      end
    end

    private

    def spec_dir_for_root
      read_default_path_from_rspec(@working_dir) || DEFAULT_SPEC_DIR
    end

    def read_default_path_from_rspec(dir)
      rspec_file = File.join(dir, '.rspec')
      return nil unless File.readable?(rspec_file)

      line = File.readlines(rspec_file).find { |l| l.strip.start_with?('--default-path') }
      return nil unless line

      line.sub(/\A--default-path\s+/, '').strip
    end

    def discover_single
      dir = spec_dir
      return [] unless dir && Dir.exist?(dir)

      pattern = File.join(dir, DEFAULT_PATTERN)
      Dir.glob(pattern).map { |p| Pathname.new(p).relative_path_from(Pathname.new(@working_dir)).to_s }.sort
    end

    def discover_umbrella
      roots = component_roots
      return [] if roots.empty?

      files = []
      roots.each do |component_root|
        base = component_root.empty? ? @working_dir : File.join(@working_dir, component_root)
        spec_path = read_default_path_from_rspec(base) || DEFAULT_SPEC_DIR
        spec_full = File.join(base, spec_path)
        next unless Dir.exist?(spec_full)

        pattern = File.join(spec_full, DEFAULT_PATTERN)
        Dir.glob(pattern).each do |p|
          rel = Pathname.new(p).relative_path_from(Pathname.new(@working_dir)).to_s
          files << rel
        end
      end
      files.sort
    end

    def flat_spec_list_for_umbrella
      discover
    end

    def run_context_umbrella(display_path)
      path_str = display_path.to_s
      line_suffix = nil
      if path_str =~ /\A(.+):(\d+)\z/
        path_str = Regexp.last_match(1)
        line_suffix = ":#{Regexp.last_match(2)}"
      end

      roots = component_roots
      roots_with_prefix = roots.map do |r|
        base = r.empty? ? @working_dir : File.join(@working_dir, r)
        spec_subdir = read_default_path_from_rspec(base) || DEFAULT_SPEC_DIR
        prefix = r.empty? ? "#{spec_subdir}/" : "#{r}/#{spec_subdir}/"
        [r, prefix]
      end
      roots_with_prefix.sort_by! { |_r, p| -p.length }

      roots_with_prefix.each do |component_root, prefix|
        next unless path_str == prefix.chomp('/') || path_str.start_with?(prefix)

        run_cwd = component_root.empty? ? @working_dir : File.join(@working_dir, component_root)
        rspec_path = if component_root.empty?
                       path_str
                     else
                       path_str.sub(%r{\A#{Regexp.escape(component_root)}/?}, '')
                     end
        rspec_path += line_suffix if line_suffix
        return { run_cwd: run_cwd, rspec_path: rspec_path }
      end

      { run_cwd: @working_dir, rspec_path: display_path }
    end
  end
end
