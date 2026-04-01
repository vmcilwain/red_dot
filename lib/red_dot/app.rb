# frozen_string_literal: true

require 'bubbletea'
require 'lipgloss'

require_relative 'border'
require_relative 'config'
require_relative 'display_row'
require_relative 'editor_launcher'
require_relative 'example_discovery'
require_relative 'file_watcher'
require_relative 'messages'
require_relative 'modal'
require_relative 'fuzzy'
require_relative 'result_paths'
require_relative 'tui_text'

require_relative 'app/key_handlers'
require_relative 'app/file_list_keys'
require_relative 'app/find_keys'
require_relative 'app/options_keys'
require_relative 'app/results_keys'
require_relative 'app/file_list_view'
require_relative 'app/panel_views'
require_relative 'app/results_view'
require_relative 'app/status_view'
require_relative 'app/display_rows'
require_relative 'app/selection'
require_relative 'app/run_manager'
require_relative 'app/run_output'
require_relative 'app/index_manager'
require_relative 'app/file_watch_handler'

module RedDot
  class App
    include Bubbletea::Model
    include FuzzySearch
    include TuiText
    include KeyHandlers
    include FileListKeys
    include FindKeys
    include OptionsKeys
    include ResultsKeys
    include FileListView
    include PanelViews
    include ResultsView
    include StatusView
    include DisplayRows
    include Selection
    include RunManager
    include RunOutput
    include IndexManager
    include FileWatchHandler

    LEFT_PANEL_RATIO = 0.38
    OPTIONS_BAR_HEIGHT = 3
    STATUS_HEIGHT = 1

    # @param working_dir [String] project root
    # @param option_overrides [Hash] merged into loaded config (e.g. :tags, :format, :fail_fast)
    def initialize(working_dir: Dir.pwd, option_overrides: {})
      @working_dir = File.expand_path(working_dir)
      @discovery = SpecDiscovery.new(working_dir: @working_dir)
      @spec_files = @discovery.discover
      @grouped = @discovery.discover_grouped_by_dir
      @cursor = 0
      @selected = {}
      @expanded_files = Set.new
      @examples_by_file = {}
      @screen = :file_list
      @options = Config.load(working_dir: @working_dir)
      apply_option_overrides(option_overrides)
      @run_pid = nil
      @run_stdout = nil
      @run_json_path = nil
      @run_output = []
      @run_output_scroll = 0
      @last_result = nil
      @last_run_paths = nil
      @last_run_component_root = nil
      @run_failed_paths = nil
      @run_queue = nil
      @width = 80
      @height = 24
      @options_cursor = 0
      @options_editing = nil
      @options_edit_buffer = ''
      @options_field_keys = %i[line_number seed format fail_fast full_output tags_str out_path example_filter editor]
      @results_cursor = 0
      @file_list_scroll_offset = 0
      @results_scroll_offset = 0
      @results_failed_line_indices = []
      @results_total_lines = 0
      @input_prompt = nil
      @find_buffer = nil
      @options_focus = false
      @index_files = []
      @index_current = 0
      @index_total = 0
      @index_result_queue = Queue.new
      @index_thread = nil
      @file_watcher = nil
      @file_watch_queue = Queue.new
      @help_visible = false
      setup_styles
    end

    # @return [Array<(self, nil)>]
    def init
      start_file_watcher if @options[:auto_index]
      return start_background_index if @options[:auto_index] && auto_index_needed?

      [self, nil]
    end

    def shutdown
      @file_watcher&.stop
      @index_thread&.join(1)
    end

    # Merges overrides into @options (tags, format, out_path, fail_fast, seed, editor, etc.).
    def apply_option_overrides(overrides)
      Config.merge_overrides!(@options, overrides)
    end

    # Handles WindowSizeMessage, RspecStartedMessage, TickMessage, KeyMessage, MouseMessage.
    def update(message)
      case message
      when Bubbletea::WindowSizeMessage
        @width = message.width
        @height = message.height
        [self, nil]
      when RspecStartedMessage
        @run_pid = message.pid
        @run_stdout = message.stdout_io
        @run_json_path = message.json_path
        @last_run_component_root = message.component_root if message.respond_to?(:component_root) && message.component_root
        @run_output = []
        @run_output_scroll = 0
        @screen = :running
        [self, schedule_tick]
      when TickMessage
        if @index_thread&.alive? || !@index_result_queue.empty?
          drain_index_results
          drain_file_watch_events
          return [self, schedule_tick] if @index_thread&.alive?

          finalize_background_index
          [self, @run_pid ? schedule_tick : schedule_idle_tick_if_watching]
        elsif @screen == :running && @run_pid
          read_run_output
          drain_file_watch_events
          pid_done = Process.wait(@run_pid, Process::WNOHANG) rescue nil
          if pid_done
            drain_run_output
            @run_stdout&.close
            @run_stdout = nil
            @run_pid = nil
            after_run_process_exits
          else
            [self, schedule_tick]
          end
        else
          drain_file_watch_events
          [self, schedule_idle_tick_if_watching]
        end
      when Bubbletea::KeyMessage
        handle_key(message)
      when Bubbletea::MouseMessage
        handle_mouse(message)
      else
        [self, nil]
      end
    end

    # Full rendered TUI string (bordered panels + status).
    def view
      main_h = [@height - STATUS_HEIGHT - OPTIONS_BAR_HEIGHT, 5].max
      left_w = [(LEFT_PANEL_RATIO * @width).floor, 24].max
      right_w = [@width - left_w, 20].max

      left_inner_h = [main_h - 2, 1].max
      right_inner_h = left_inner_h

      options_content = build_options_bar_content
      left_lines = build_file_list_lines(left_inner_h)
      center_lines = build_center_panel_lines(right_inner_h)

      opts_title = @options_focus ? '1 Options' : 'Options'
      opts_box = Border.render(
        width: @width, height: OPTIONS_BAR_HEIGHT,
        title: opts_title, lines: options_content,
        active: focused_panel == 1,
        active_style: @active_border_style, inactive_style: @inactive_border_style
      )

      file_title = @find_buffer ? '2 Find' : '2 Spec files'
      left_box = Border.render(
        width: left_w, height: main_h,
        title: file_title, lines: left_lines,
        active: focused_panel == 2,
        active_style: @active_border_style, inactive_style: @inactive_border_style
      )

      right_title = center_panel_title
      right_box = Border.render(
        width: right_w, height: main_h,
        title: right_title, lines: center_lines,
        active: focused_panel.zero?,
        active_style: @active_border_style, inactive_style: @inactive_border_style
      )

      left_arr = left_box.split("\n")
      right_arr = right_box.split("\n")
      main_rows = main_h.times.map do |i|
        l = left_arr[i] || ''.ljust(left_w)
        r = right_arr[i] || ''.ljust(right_w)
        "#{l}#{r}"
      end

      status = @help_style.render(truncate_plain(status_line, @width).ljust(@width))
      base = [opts_box, main_rows.join("\n"), status].join("\n")

      return render_modal_overlay(base) if @input_prompt || @help_visible

      base
    end

    private

    def setup_styles
      @active_border_style = Lipgloss::Style.new.bold(true).foreground('#106EBE')
      @inactive_border_style = Lipgloss::Style.new.foreground('241')
      @help_style = Lipgloss::Style.new.foreground('#5A9FD4')
      @pass_style = Lipgloss::Style.new.foreground('2').bold(true)
      @fail_style = Lipgloss::Style.new.foreground('9')
      @warn_style = Lipgloss::Style.new.foreground('11').bold(true)
      @muted_style = Lipgloss::Style.new.foreground('241')
      @selected_line_style = Lipgloss::Style.new.background('#0D3B66')
      @inactive_selected_style = Lipgloss::Style.new.bold(true)
      @cursor_style = Lipgloss::Style.new.foreground('255').background('#106EBE').bold(true)
    end

    def center_panel_title
      case @screen
      when :indexing then '0 Indexing'
      when :running then '0 Running'
      when :results then '0 Results'
      else '0 Output'
      end
    end

    def render_modal_overlay(base)
      if @help_visible
        render_help_modal(base)
      elsif @input_prompt
        render_input_modal(base)
      else
        base
      end
    end

    def render_input_modal(base)
      modal_w = [50, @width - 4].min
      content = [
        " #{@input_prompt[:message]}#{@input_prompt[:buffer]}_",
        '',
        @help_style.render(' Enter: run  Esc: cancel')
      ]
      modal_h = content.size + 2
      modal_box = Border.render(
        width: modal_w, height: modal_h,
        title: 'Run at line', lines: content,
        active: true,
        active_style: @active_border_style, inactive_style: @inactive_border_style
      )
      Modal.overlay(base, modal_box, @width, @height, modal_w, modal_h)
    end

    def render_help_modal(base)
      modal_w = [60, @width - 4].min
      content = help_content_for_context
      modal_h = [content.size + 2, @height - 4].min
      modal_box = Border.render(
        width: modal_w, height: modal_h,
        title: 'Keybindings', lines: content,
        active: true,
        active_style: @active_border_style, inactive_style: @inactive_border_style
      )
      Modal.overlay(base, modal_box, @width, @height, modal_w, modal_h)
    end

    def help_content_for_context
      common = [
        @muted_style.render(' Navigation'),
        ' 1/2/0    Focus panel     Tab  Cycle panels',
        ' j/k      Move up/down    g/G  Top/Bottom',
        ' PgUp/Dn  Page scroll     ?    This help',
        ' q        Quit',
        ''
      ]
      case @screen
      when :file_list
        common + [
          @muted_style.render(' File List'),
          ' /        Find            I    Index specs',
          ' →/←      Expand/Collapse ]/[  Expand/Collapse all',
          ' Ctrl+T   Toggle select   a    Run all',
          ' s        Run selected    e    Run example/line',
          ' f        Run failed      O    Open in editor',
          ' o        Focus options   R    Refresh'
        ]
      when :results
        common + [
          @muted_style.render(' Results'),
          ' e        Run example     O    Open in editor',
          ' r        Rerun           f    Run failed',
          ' b/Esc    Back to files'
        ]
      when :running
        common + [
          @muted_style.render(' Running'),
          ' j/k      Scroll output   q    Kill run',
          ' 2        Back to files'
        ]
      else
        common
      end
    end

    def focused_panel
      return 1 if @options_focus
      return 0 if @screen == :results || @screen == :running || @screen == :indexing

      2
    end

    def schedule_tick
      Bubbletea.tick(0.05) { TickMessage.new }
    end

    def schedule_idle_tick
      Bubbletea.tick(0.5) { TickMessage.new }
    end

    def apply_panel_focus_digit(digit)
      case digit
      when 1
        @options_focus = true
        @screen = :file_list
      when 2
        @options_focus = false
        @screen = :file_list
      when 0, 3
        @options_focus = false
        if @run_pid
          @screen = :running
        elsif @last_result
          @screen = :results
        end
      end
    end

    def refresh_spec_list
      sync_spec_files_from_disk
      @expanded_files = Set.new
      @examples_by_file = {}
      @find_buffer = nil
      @cursor = 0
      [self, nil]
    end

    def sync_spec_files_from_disk
      @spec_files = @discovery.discover
      @grouped = @discovery.discover_grouped_by_dir
    end

    def flat_spec_list
      @grouped.flat_map { |_dir, files| files }
    end

    def file_list_visible_height(content_h)
      header_count = 2
      header_count += 1 if @find_buffer
      header_count += 1 if index_stale_hint_line
      [content_h - header_count, 1].max
    end

    def run_output_visible_height(content_h)
      [content_h - 4, 1].max
    end
  end
end
