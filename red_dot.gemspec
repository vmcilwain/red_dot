# frozen_string_literal: true

require_relative 'lib/red_dot/version'

Gem::Specification.new do |spec|
  spec.name = 'red_dot'
  spec.version = RedDot::VERSION
  spec.authors = ['Lovell McIlwain']
  spec.email = ['']

  spec.summary = 'Terminal UI for running RSpec tests (hopefully easier)'
  spec.description = 'A lazy-like TUI for running RSpec tests: select files, set options ' \
                     '(tags, format, output, seed), run all/some/one, view results, and rerun.'
  spec.homepage = 'https://github.com/vmcilwain/red_dot'
  spec.required_ruby_version = '>= 3.2.0'
  spec.licenses = ['MIT']

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir['lib/**/*', 'exe/**/*'] + %w[README.md LICENSE]
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'bubbletea', '~> 0.1'
  spec.add_dependency 'lipgloss', '~> 0.1'
end
