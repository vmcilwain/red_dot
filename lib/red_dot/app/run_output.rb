# frozen_string_literal: true

module RedDot
  class App
    module RunOutput
      private

      def read_run_output
        return unless @run_stdout

        content_h = [@height - STATUS_HEIGHT - OPTIONS_BAR_HEIGHT, 5].max
        run_visible = run_output_visible_height(content_h)
        was_at_bottom = @run_output.size <= run_visible || @run_output_scroll >= [@run_output.size - run_visible, 0].max

        @run_stdout.read_nonblock(4096).each_line { |line| @run_output << line.chomp }

        return unless was_at_bottom

        @run_output_scroll = [@run_output.size - run_visible, 0].max
      rescue IO::WaitReadable, EOFError
        # no more data
      end

      def drain_run_output
        return unless @run_stdout

        content_h = [@height - STATUS_HEIGHT - OPTIONS_BAR_HEIGHT, 5].max
        run_visible = run_output_visible_height(content_h)
        was_at_bottom = @run_output.size <= run_visible || @run_output_scroll >= [@run_output.size - run_visible, 0].max

        loop do
          chunk = @run_stdout.read(4096)
          break if chunk.nil? || chunk.empty?

          chunk.each_line { |line| @run_output << line.chomp }
        end

        return unless was_at_bottom

        @run_output_scroll = [@run_output.size - run_visible, 0].max
      rescue IOError, Errno::EPIPE
        # pipe closed or broken
      end

      def after_run_process_exits
        return spawn_next_queued_rspec if @run_queue&.any?

        @run_queue = nil
        @last_result = RspecResult.from_json_path(@run_json_path)
        raw_failures = @last_result&.failure_locations || []
        @run_failed_paths = ResultPaths.normalize_failure_locations(raw_failures, @last_run_component_root)
        @screen = :results
        @results_cursor = 0
        @results_scroll_offset = 0
        [self, nil]
      end

      def spawn_next_queued_rspec
        next_group = @run_queue.shift
        opts = { working_dir: next_group[:run_cwd], paths: next_group[:rspec_paths],
                 tags: @options[:tags].empty? ? Config.parse_tags(@options[:tags_str]) : @options[:tags],
                 format: @options[:format], out_path: @options[:out_path].to_s.strip,
                 example_filter: @options[:example_filter].to_s.strip, fail_fast: @options[:fail_fast],
                 seed: @options[:seed].to_s.strip }
        opts[:out_path] = nil if opts[:out_path].to_s.empty?
        opts[:example_filter] = nil if opts[:example_filter].to_s.empty?
        opts[:seed] = nil if opts[:seed].to_s.empty?
        data = RspecRunner.spawn(**opts)
        @run_pid = data[:pid]
        @run_stdout = data[:stdout_io]
        @run_json_path = data[:json_path]
        @last_run_component_root = next_group[:component_root]
        [self, schedule_tick]
      end
    end
  end
end
