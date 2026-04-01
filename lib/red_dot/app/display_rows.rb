# frozen_string_literal: true

module RedDot
  class App
    module DisplayRows
      private

      def load_examples_for(path)
        return @examples_by_file[path] if @examples_by_file.key?(path)

        ctx = @discovery.run_context_for(path)
        run_cwd = ctx[:run_cwd]
        rspec_path = ctx[:rspec_path]
        examples = ExampleDiscovery.get_cached_examples(run_cwd, rspec_path)
        examples = ExampleDiscovery.discover(working_dir: run_cwd, path: rspec_path) if examples.nil?
        @examples_by_file[path] = examples
        examples
      end

      def build_full_display_rows
        rows = []
        flat_spec_list.each do |path|
          rows << DisplayRow.new(type: :file, path: path, line_number: nil, full_description: nil)
          next unless @expanded_files.include?(path)

          load_examples_for(path).each do |ex|
            rows << DisplayRow.new(type: :example, path: path, line_number: ex.line_number,
                                   full_description: ex.full_description)
          end
        end
        rows
      end

      def cached_examples_for(path)
        return @examples_by_file[path] if @examples_by_file.key?(path)

        ctx = @discovery.run_context_for(path)
        examples = ExampleDiscovery.get_cached_examples(ctx[:run_cwd], ctx[:rspec_path])
        examples || []
      end

      def build_filtered_display_rows
        q = @find_buffer.to_s.strip.downcase
        return build_full_display_rows if q.empty?

        rows = []
        flat_spec_list.each do |path|
          file_matches = fuzzy_match_string?(path, q)
          examples = cached_examples_for(path)
          example_matches = examples.select { |ex| fuzzy_match_string?(ex.full_description.to_s, q) }
          next unless file_matches || example_matches.any?

          @expanded_files.add(path) if example_matches.any?
          rows << DisplayRow.new(type: :file, path: path, line_number: nil, full_description: nil)
          (file_matches ? examples : example_matches).each do |ex|
            rows << DisplayRow.new(type: :example, path: path, line_number: ex.line_number,
                                   full_description: ex.full_description)
          end
        end
        rows
      end

      def display_rows
        if @find_buffer.nil? || @find_buffer.to_s.strip.empty?
          build_full_display_rows
        else
          build_filtered_display_rows
        end
      end

      def current_spec_list
        display_rows
      end
    end
  end
end
