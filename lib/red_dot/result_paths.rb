# frozen_string_literal: true

module RedDot
  # Display paths for RSpec JSON failures when runs use a component (umbrella) cwd.
  module ResultPaths
    module_function

    # @param locations [Array] raw failure locations from JSON (paths relative to component cwd)
    # @param component_root [String, nil] relative prefix for display (e.g. "components/a"), or nil if not a component run
    # @return [Array]
    def normalize_failure_locations(locations, component_root)
      return locations if locations.nil? || locations.empty?
      return locations unless component_root

      locations.map do |loc|
        if loc.to_s.include?(':')
          file, line = loc.to_s.split(':', 2)
          display_file = component_root.empty? ? file : "#{component_root}/#{file}"
          "#{display_file}:#{line}"
        else
          component_root.empty? ? loc : "#{component_root}/#{loc}"
        end
      end
    end

    # @param file_path [String]
    # @param component_root [String, nil]
    # @return [String]
    def display_path_for_result_file(file_path, component_root)
      return file_path.to_s if file_path.to_s.strip.empty?
      return file_path.to_s unless component_root

      if component_root.empty?
        file_path.to_s
      else
        "#{component_root}/#{file_path}"
      end
    end
  end
end
