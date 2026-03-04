# frozen_string_literal: true

require 'tempfile'

module RedDot
  class RspecRunner
    def self.spawn(working_dir:, paths:, tags: [], format: 'progress', out_path: nil,
                   example_filter: nil, fail_fast: false, seed: nil)
      json_file = Tempfile.new(['red_dot', '.json'])
      json_path = json_file.path
      json_file.close
      json_file.unlink

      argv = build_argv(
        paths: paths,
        json_path: json_path,
        format: format,
        out_path: out_path,
        tags: tags,
        example_filter: example_filter,
        fail_fast: fail_fast,
        seed: seed
      )

      stdout_r, stdout_w = IO.pipe
      stdout_w.close_on_exec = true

      env = {}
      env['BUNDLE_GEMFILE'] = File.join(working_dir, 'Gemfile') if File.file?(File.join(working_dir, 'Gemfile'))

      cmd = rspec_command(working_dir)
      pid = Kernel.spawn(env, *cmd, *argv, out: stdout_w, err: stdout_w, chdir: working_dir)
      stdout_w.close

      { pid: pid, stdout_io: stdout_r, json_path: json_path }
    end

    def self.build_argv(paths:, json_path:, format: 'progress', out_path: nil, tags: [],
                        example_filter: nil, fail_fast: false, seed: nil)
      argv = paths.dup
      argv << '--format' << 'json' << '--out' << json_path
      argv << '--format' << format
      tags.each { |t| argv << '--tag' << t }
      argv << '--out' << out_path if out_path.to_s.strip != ''
      argv << '--example' << example_filter if example_filter.to_s.strip != ''
      argv << '--fail-fast' if fail_fast
      argv << '--seed' << seed.to_s.strip if seed.to_s.strip =~ /\A\d+\z/
      argv
    end

    def self.rspec_command(working_dir)
      gemfile = File.join(working_dir, 'Gemfile')
      File.file?(gemfile) ? %w[bundle exec rspec] : ['rspec']
    end

    def self.run_dry_run(working_dir:, paths:)
      json_file = Tempfile.new(['red_dot_list', '.json'])
      json_path = json_file.path
      json_file.close
      json_file.unlink
      argv = paths.dup
      argv << '--dry-run' << '--format' << 'json' << '--out' << json_path
      env = {}
      env['BUNDLE_GEMFILE'] = File.join(working_dir, 'Gemfile') if File.file?(File.join(working_dir, 'Gemfile'))
      cmd = rspec_command(working_dir)
      pid = Kernel.spawn(env, *cmd, *argv, out: File::NULL, err: File::NULL, chdir: working_dir)
      Process.wait(pid)
      json_path
    end
  end
end
