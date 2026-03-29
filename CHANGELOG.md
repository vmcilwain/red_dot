# Changelog

All notable changes to Red Dot are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased](https://github.com/vmcilwain/red_dot/compare/v0.2.0...HEAD)

### Added

- **Screenshot** in the repository for documentation.
- **`Config.merge_overrides!`**: single entry point for merging CLI- and YAML-style option hashes into options (used by `merge_file` and `App#apply_option_overrides`).
- **Modular TUI code**: `DisplayRow`, Bubbletea message classes (`RspecStartedMessage`, `TickMessage`, etc.), `FuzzySearch`, and `TuiText` extracted from `App` for clearer structure and tests.
- **`Config.parse_tags`**: shared parsing for comma/whitespace-separated tags (used by YAML loading and the TUI).
- **`ResultPaths`**: helpers for normalizing failure locations and display paths when runs use a component (umbrella) working directory.
- **`EditorLauncher`**: opens paths in the configured editor (`vscode`, `cursor`, or `textmate`).

### Changed

- **Selection (Ctrl+T)**: toggles selection on **example** rows (path:line) as well as whole files; selecting a file clears line-level keys for that file; selecting an example clears whole-file selection for that path; run targets dedupe when a file and its examples are both selected.
- **README**: documents that the **editor** option must be one of the built-in identifiers (not an arbitrary executable path); panel/keybinding text updated for example-level selection.
- **Internals**: `App` delegates option overrides to `Config`; tag list parsing for YAML `tags_str` goes through `parse_tags`.

### Fixed

- **`merge_overrides!`**: when only `tags_str` is supplied (no `tags` array), the `tags` array is updated from the parsed string so options stay consistent.
- **`parse_tags`**: coerces input with `to_s` before splitting so non-string values do not raise.
- **`EditorLauncher`**: a failed `Process.spawn` (e.g. missing editor binary) logs a warning instead of crashing the TUI.

## [0.2.0](https://github.com/vmcilwain/red_dot/compare/v0.1.0...v0.2.0) - 2026-03-28

### Added

- **Full output** option: after a run, show captured RSpec stdout in the results panel (scrollable) instead of the structured summary. Available in the options bar, project/user config (`full_output`), and CLI (`--full-output`).
- Mouse wheel scrolling in the TUI (`mouse_cell_motion` enabled).
- When a run finishes with errors outside of examples, append captured stdout to the structured results when available.
- Development: RSpec in the Gemfile; expanded specs for CLI, config, and app behavior.

### Changed

- **Minimum Ruby** is now **3.3** (was 3.2).
- **File selection** in the spec list and find mode: **Ctrl+T** toggles selection (replaces Space) so arrow keys can move the cursor without changing selection.
- **Running output** panel: scrollable window (not only the last 50 lines), auto-scroll when at the bottom, richer status/help (j/k, PgUp/PgDn, g/G, panel `2` while running).
- **Find mode** status line documents Home/End and Ctrl+T.
- Refactored run completion: drain remaining stdout when a process exits; clearer split of queued-run continuation vs. results handling.
- README: expanded option tables, keybinding reference, and VS Code Test Explorer wording; gemspec description line split for RuboCop line length.

### Fixed

- RuboCop `Layout/LineLength` in the gemspec (split long description line).

## [0.1.0](https://github.com/vmcilwain/red_dot/releases/tag/v0.1.0) - Initial release

- TUI for running RSpec from the terminal (bubbletea + lipgloss).
- Single-project mode: run from project root or any directory with `spec/`.
- Umbrella/component mode: run from repo root with `components/`; specs run per component with its Gemfile.
- Spec file browser: expand/collapse files, list examples per file, index (Shift+I) for search.
- Run modes: selected files, all specs, failed only, single example (path:line), find-then-run.
- Configurable options: tags, format, output path, example filter, line number, fail-fast, seed, editor.
- Config: defaults, user config (`~/.config/red_dot/config.yml`), project (`.red_dot.yml`), CLI overrides.
- CLI flags: `--format`, `--tag`, `--output`, `--example`, `--line`, `--fail-fast`, optional project path.
- Results panel: browse failures, rerun example, open in editor (vscode/cursor/textmate), rerun same scope or failed only.
- Editor option: vscode, cursor, or textmate for "open file" (O).
- Requires Ruby 3.2+ and a TTY.

