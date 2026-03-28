# frozen_string_literal: true

require 'json'

module RedDot
  # Parsed RSpec JSON result. Example: description, status, file_path, line_number, run_time, etc.
  class RspecResult
    Example = Struct.new(
      :description, :full_description, :status, :file_path, :line_number, :exception_message,
      :run_time, :pending_message, keyword_init: true
    )

    attr_reader :summary_line, :examples, :duration, :errors_outside_of_examples, :seed

    def initialize(summary_line:, examples:, duration: nil, errors_outside_of_examples: 0, seed: nil)
      @summary_line = summary_line
      @examples = examples
      @duration = duration
      @errors_outside_of_examples = errors_outside_of_examples.to_i
      @seed = seed
    end

    # @return [RspecResult, nil] parsed from JSON file
    def self.from_json_path(path)
      return nil unless path && File.readable?(path)

      raw = File.read(path)
      return nil if raw.strip.empty?

      data = JSON.parse(raw)
      examples = (data['examples'] || []).map do |ex|
        exception_msg = ex.dig('exception', 'message')
        raw_run_time = ex['run_time']
        run_time = if raw_run_time.is_a?(Numeric)
                     Float(raw_run_time)
                   elsif raw_run_time.is_a?(String) && !raw_run_time.strip.empty?
                     Float(raw_run_time)
                   end
        Example.new(
          description: ex['description'],
          full_description: ex['full_description'],
          status: ex['status']&.to_sym,
          file_path: ex['file_path'],
          line_number: ex['line_number'],
          exception_message: exception_msg,
          run_time: run_time,
          pending_message: ex['pending_message']
        )
      end
      summary = data['summary'] || {}
      new(
        summary_line: data['summary_line'] || '',
        examples: examples,
        duration: summary['duration'],
        errors_outside_of_examples: summary['errors_outside_of_examples_count'],
        seed: data['seed']
      )
    end

    def passed_count
      examples.count { |e| e.status == :passed }
    end

    def failed_count
      examples.count { |e| e.status == :failed }
    end

    def pending_count
      examples.count { |e| e.status == :pending }
    end

    def failed_examples
      examples.select { |e| e.status == :failed }
    end

    def pending_examples
      examples.select { |e| e.status == :pending }
    end

    def failure_locations
      failed_examples.map { |e| e.line_number ? "#{e.file_path}:#{e.line_number}" : e.file_path }.uniq
    end

    def examples_with_run_time
      examples.select { |e| e.run_time.is_a?(Numeric) && e.run_time.positive? }
    end

    def slowest_examples(count = 5)
      examples_with_run_time.max_by(count, &:run_time)
    end

    def fastest_examples(count = 5)
      examples_with_run_time.min_by(count, &:run_time)
    end

    def slowest_files(count = 5)
      by_file = examples_with_run_time.group_by(&:file_path)
      by_file.transform_values { |exs| exs.sum(&:run_time) }
             .max_by(count) { |_path, total| total }
             .map { |path, total| [path, total] }
    end
  end
end
