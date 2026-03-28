# frozen_string_literal: true

require_relative 'red_dot/version'
require_relative 'red_dot/config'
require_relative 'red_dot/cli'
require_relative 'red_dot/spec_discovery'
require_relative 'red_dot/example_discovery'
require_relative 'red_dot/rspec_result'
require_relative 'red_dot/rspec_runner'
require_relative 'red_dot/app'

module RedDot
  class Error < StandardError; end

  # Runs the TUI. Requires TTY. Exits with 1 if not a TTY.
  # @param working_dir [String] directory containing specs
  # @param option_overrides [Hash] e.g. :tags, :format, :out_path, :fail_fast, :seed, :editor
  def self.run(working_dir: Dir.pwd, option_overrides: {})
    unless $stdout.tty?
      warn 'Error: red_dot (rdot) requires a TTY. Run from a terminal.'
      exit 1
    end
    app = RedDot::App.new(working_dir: working_dir, option_overrides: option_overrides)
    Bubbletea.run(app, alt_screen: true, mouse_cell_motion: true)
  end
end
