# frozen_string_literal: true

module RedDot
  class App
    module ResultsView # rubocop:disable Metrics/ModuleLength -- results rendering is inherently dense
      private

      def build_results_lines_full_output(content_h)
        lines = []
        @results_failed_line_indices = []
        lines << (@last_result ? " #{@last_result.summary_line}" : @muted_style.render(' No result data.'))
        lines << ''
        if @run_output.any?
          @run_output.each { |out_line| lines << " #{out_line}" }
        else
          lines << @muted_style.render(' (No captured stdout from this run.)')
        end
        paginate_results(lines, content_h)
      end

      def build_results_lines(content_h)
        return build_results_lines_full_output(content_h) if @options[:full_output]

        lines = []
        @results_failed_line_indices = []
        if @last_result
          build_results_summary(lines)
          build_results_timing(lines)
          build_results_pending(lines)
          build_results_slowest_files(lines)
          build_results_failures(lines)
        else
          lines << @muted_style.render(' No result data.')
        end
        paginate_results(lines, content_h)
      end

      def build_results_summary(lines)
        r = @last_result
        lines << " #{r.summary_line}"
        total = r.examples.size
        pass_pct = total.positive? ? ((r.passed_count.to_f / total) * 100).round : 0
        metrics = ["Pass: #{r.passed_count}/#{total} (#{pass_pct}%)"]
        metrics << "Total: #{format_run_time(r.duration)}" if r.duration.is_a?(Numeric)
        metrics << "Seed: #{r.seed}" if r.seed
        lines << @muted_style.render(" #{metrics.join('  |  ')}")
        return unless r.errors_outside_of_examples.positive?

        lines << @warn_style.render(" #{r.errors_outside_of_examples} error(s) outside examples")
        return unless @run_output.any?

        lines << ''
        lines << @muted_style.render(' Output:')
        @run_output.each { |out_line| lines << "  #{out_line}" }
        lines << ''
      end

      def build_results_timing(lines)
        r = @last_result
        return unless r.examples_with_run_time.any?

        lines << ''
        lines << @muted_style.render(' Slowest:')
        r.slowest_examples(5).each do |ex|
          loc = [ex.file_path, ex.line_number].compact.join(':')
          lines << "  #{format_run_time(ex.run_time)}  #{loc} #{ex.description}"
        end
        lines << ''
        lines << @muted_style.render(' Fastest:')
        r.fastest_examples(5).each do |ex|
          loc = [ex.file_path, ex.line_number].compact.join(':')
          lines << "  #{format_run_time(ex.run_time)}  #{loc} #{ex.description}"
        end
        lines << ''
      end

      def build_results_pending(lines)
        r = @last_result
        return unless r.pending_count.positive?

        lines << @muted_style.render(' Pending:')
        r.pending_examples.each do |ex|
          loc = [ex.file_path, ex.line_number].compact.join(':')
          lines << "  #{loc} #{ex.description}"
          lines << @muted_style.render("    #{ex.pending_message}") if ex.pending_message.to_s.strip != ''
        end
        lines << ''
      end

      def build_results_slowest_files(lines)
        r = @last_result
        return unless r.examples_with_run_time.any? && r.slowest_files(5).any?

        lines << @muted_style.render(' Slowest files:')
        r.slowest_files(5).each do |path, total_sec|
          lines << "  #{format_run_time(total_sec)}  #{path}"
        end
        lines << ''
      end

      def build_results_failures(lines)
        r = @last_result
        return unless r.failed_count.positive?

        lines << @muted_style.render(' Failed:')
        r.failed_examples.each_with_index do |ex, i|
          @results_failed_line_indices << lines.size
          loc_path = ResultPaths.display_path_for_result_file(ex.file_path, @last_run_component_root)
          line_text = " #{loc_path}:#{ex.line_number} #{ex.description}"
          lines << (i == @results_cursor ? @cursor_style.render(line_text) : @fail_style.render(line_text))
          lines << @muted_style.render("   #{ex.exception_message&.lines&.first&.strip}") if ex.exception_message
        end
      end

      def paginate_results(lines, content_h)
        @results_total_lines = lines.size
        max_scroll = [@results_total_lines - content_h, 0].max
        @results_scroll_offset = [[@results_scroll_offset, max_scroll].min, 0].max
        if @results_failed_line_indices.any? && @results_cursor < @results_failed_line_indices.size
          cursor_line = @results_failed_line_indices[@results_cursor]
          if cursor_line < @results_scroll_offset
            @results_scroll_offset = cursor_line
          elsif cursor_line >= @results_scroll_offset + content_h
            @results_scroll_offset = cursor_line - content_h + 1
          end
        end
        lines[@results_scroll_offset, content_h] || []
      end
    end
  end
end
