# frozen_string_literal: true

require 'bubbletea'

module RedDot
  # Message sent when an RSpec run has started. Carries pid, stdout IO, JSON path, optional component_root.
  class RspecStartedMessage < Bubbletea::Message
    attr_reader :pid, :stdout_io, :json_path, :component_root

    def initialize(pid:, stdout_io:, json_path:, component_root: nil)
      @pid = pid
      @stdout_io = stdout_io
      @json_path = json_path
      @component_root = component_root
    end
  end

  class TickMessage < Bubbletea::Message; end
end
