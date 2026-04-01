# frozen_string_literal: true

module RedDot
  class FileWatcher
    attr_reader :listener

    # @param spec_dirs [Array<String>] absolute paths to spec directories
    # @param on_change [#call] callback receiving (modified, added, removed) arrays
    # @return [FileWatcher, nil] nil if listen gem is unavailable
    def self.start(spec_dirs:, on_change:)
      return nil if spec_dirs.empty?

      require 'listen'
      watcher = new(spec_dirs: spec_dirs, on_change: on_change)
      watcher.start
      watcher
    rescue LoadError
      nil
    end

    def initialize(spec_dirs:, on_change:)
      @on_change = on_change
      @listener = Listen.to(
        *spec_dirs,
        only: /_spec\.rb$/,
        wait_for_delay: 0.5,
        latency: 0.3
      ) do |modified, added, removed|
        @on_change.call(modified, added, removed)
      end
    end

    def start
      @listener&.start
    end

    def stop
      @listener&.stop
    end

    def paused?
      @listener&.paused? || false
    end
  end
end
