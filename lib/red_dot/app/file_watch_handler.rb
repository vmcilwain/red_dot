# frozen_string_literal: true

module RedDot
  class App
    module FileWatchHandler
      private

      def start_file_watcher
        queue = @file_watch_queue
        @file_watcher = FileWatcher.start(
          spec_dirs: discover_watch_dirs,
          on_change: proc { |modified, added, removed| queue << { modified: modified, added: added, removed: removed } }
        )
      rescue StandardError
        @file_watcher = nil
      end

      def discover_watch_dirs
        if @discovery.umbrella?
          dirs = @discovery.component_roots.map do |root|
            base = root.empty? ? @working_dir : File.join(@working_dir, root)
            File.join(base, SpecDiscovery::DEFAULT_SPEC_DIR)
          end
          dirs.select { |d| Dir.exist?(d) }
        else
          dir = @discovery.spec_dir
          Dir.exist?(dir) ? [dir] : []
        end
      end

      def schedule_idle_tick_if_watching
        @file_watcher ? schedule_idle_tick : nil
      end

      def drain_file_watch_events
        dirty_paths = []
        removed_paths = []

        until @file_watch_queue.empty?
          begin
            event = @file_watch_queue.pop(true)
            dirty_paths.concat((event[:modified] + event[:added]).select { |f| f.end_with?('_spec.rb') })
            removed_paths.concat(event[:removed].select { |f| f.end_with?('_spec.rb') })
          rescue ThreadError
            break
          end
        end

        removed_paths.uniq.each do |abs_path|
          rel = Pathname.new(abs_path).relative_path_from(Pathname.new(@working_dir)).to_s
          ctx = @discovery.run_context_for(rel)
          ExampleDiscovery.purge_cached_path(ctx[:run_cwd], ctx[:rspec_path])
          @examples_by_file.delete(rel)
        end

        return if dirty_paths.empty?

        sync_spec_files_from_disk
        start_background_index unless @index_thread&.alive?
      end
    end
  end
end
