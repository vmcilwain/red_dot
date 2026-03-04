# frozen_string_literal: true

require_relative "lib/red_dot/version"

Gem::Specification.new do |spec|
  spec.name = "red_dot"
  spec.version = RedDot::VERSION
  spec.authors = ["Red Dot Contributors"]
  spec.email = [""]

  spec.summary = "Terminal UI for running RSpec tests"
  spec.description = "A long-running TUI (like lazygit) for running RSpec tests: select files, set options (tags, format, output), run all/some/one, view results, and rerun without restarting."
  spec.homepage = "https://github.com/red_dot/red_dot"
  spec.required_ruby_version = ">= 3.2.0"
  spec.licenses = ["MIT"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*", "exe/**/*"] + %w[README.md LICENSE]
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "bubbletea", "~> 0.1"
  spec.add_dependency "lipgloss", "~> 0.1"
end
