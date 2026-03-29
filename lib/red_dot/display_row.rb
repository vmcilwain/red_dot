# frozen_string_literal: true

module RedDot
  # One row in the file/example list. { type: :file | :example, path, line_number, full_description }.
  DisplayRow = Struct.new(:type, :path, :line_number, :full_description, keyword_init: true) do
    def file_row?
      type == :file
    end

    def example_row?
      type == :example
    end

    # Path to run: path for file, path:line for example.
    def runnable_path
      example_row? ? "#{path}:#{line_number}" : path
    end

    def row_id
      example_row? ? "#{path}:#{line_number}" : path
    end
  end
end
