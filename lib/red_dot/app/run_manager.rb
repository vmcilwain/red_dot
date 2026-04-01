# frozen_string_literal: true

module RedDot
  class App
    module RunManager
      private

      def apply_line_number_to_paths(paths)
        line = @options[:line_number].to_s.strip
        return paths if line.empty?
        return paths unless paths.size == 1 && paths[0].to_s !~ /:\d+\z/
        return paths unless line.match?(/\A\d+\z/)

        ["#{paths[0]}:#{line}"]
      end

      def run_specs(paths)
        paths = apply_line_number_to_paths(paths)
        @last_run_paths = paths
        tags = @options[:tags].empty? ? Config.parse_tags(@options[:tags_str]) : @options[:tags]
        format = @options[:format]
        out_path = @options[:out_path].to_s.strip
        out_path = nil if out_path.empty?
        example_filter = @options[:example_filter].to_s.strip
        example_filter = nil if example_filter.empty?
        seed = @options[:seed].to_s.strip
        seed = nil if seed.empty?

        groups = group_paths_by_run_context(paths)
        spawn_run_groups(groups, tags: tags, format: format, out_path: out_path,
                                 example_filter: example_filter, seed: seed)
      end

      def spawn_run_groups(groups, tags:, format:, out_path:, example_filter:, seed:)
        if groups.size == 1
          g = groups.first
          opts = build_run_opts(g, tags: tags, format: format, out_path: out_path,
                                   example_filter: example_filter, seed: seed)
          [self, -> { spawn_rspec(opts, g[:component_root]) }]
        else
          @run_queue = groups
          first = @run_queue.shift
          opts = build_run_opts(first, tags: tags, format: format, out_path: out_path,
                                       example_filter: example_filter, seed: seed)
          [self, -> { spawn_rspec(opts, first[:component_root]) }]
        end
      end

      def build_run_opts(group, tags:, format:, out_path:, example_filter:, seed:)
        { working_dir: group[:run_cwd], paths: group[:rspec_paths], tags: tags, format: format,
          out_path: out_path, example_filter: example_filter, fail_fast: @options[:fail_fast], seed: seed }
      end

      def spawn_rspec(opts, component_root)
        data = RspecRunner.spawn(**opts)
        RspecStartedMessage.new(pid: data[:pid], stdout_io: data[:stdout_io],
                                json_path: data[:json_path], component_root: component_root)
      end

      def group_paths_by_run_context(paths)
        by_cwd = Hash.new { |h, k| h[k] = { run_cwd: k, rspec_paths: [], component_root: nil } }
        paths.each do |display_path|
          ctx = @discovery.run_context_for(display_path)
          run_cwd = ctx[:run_cwd]
          component_root = @discovery.umbrella? ? relative_component_root(run_cwd) : nil
          by_cwd[run_cwd][:rspec_paths] << ctx[:rspec_path]
          by_cwd[run_cwd][:component_root] = component_root
        end
        by_cwd.values
      end

      def relative_component_root(run_cwd)
        return '' if run_cwd == @working_dir

        Pathname.new(run_cwd).relative_path_from(Pathname.new(@working_dir)).to_s
      end

      def kill_run
        return unless @run_pid

        Process.kill('TERM', @run_pid) rescue nil
        Process.wait(@run_pid) rescue nil
        drain_run_output
        @run_stdout&.close
        @run_stdout = nil
        @run_pid = nil
        @run_queue = nil
      end
    end
  end
end
