# frozen_string_literal: true

module RedDot
  class App
    module IndexManager
      private

      def auto_index_needed?
        paths = flat_spec_list
        paths.any? && ExampleDiscovery.stale_paths(@discovery, paths).any?
      end

      def start_background_index(force: false)
        return [self, nil] if @index_thread&.alive?

        sync_spec_files_from_disk
        files = flat_spec_list
        return [self, nil] if files.empty?

        stale = force ? files : ExampleDiscovery.stale_paths(@discovery, files)
        return [self, nil] if stale.empty?

        @index_files = stale
        @index_current = 0
        @index_total = stale.size
        @screen = :indexing
        @index_result_queue = Queue.new

        queue = @index_result_queue
        discovery = @discovery
        paths_to_index = stale.dup

        @index_thread = Thread.new do
          by_cwd = Hash.new { |h, k| h[k] = [] }
          paths_to_index.each do |display_path|
            ctx = discovery.run_context_for(display_path)
            by_cwd[ctx[:run_cwd]] << { display_path: display_path, rspec_path: ctx[:rspec_path] }
          end

          by_cwd.each do |run_cwd, entries|
            rspec_paths = entries.map { |e| e[:rspec_path] }
            results = ExampleDiscovery.discover_batch(working_dir: run_cwd, paths: rspec_paths)
            entries.each do |entry|
              queue << { type: :progress, display_path: entry[:display_path], examples: results[entry[:rspec_path]] || [] }
            end
          end
          queue << { type: :done }
        rescue StandardError => e
          queue << { type: :error, message: e.message }
        end

        [self, schedule_tick]
      end

      def drain_index_results
        until @index_result_queue.empty?
          begin
            msg = @index_result_queue.pop(true)
            case msg[:type]
            when :progress
              @examples_by_file[msg[:display_path]] = msg[:examples]
              @index_current += 1
            when :done, :error
              break
            end
          rescue ThreadError
            break
          end
        end
      end

      def finalize_background_index
        @index_thread = nil
        @screen = :file_list if @screen == :indexing
      end
    end
  end
end
