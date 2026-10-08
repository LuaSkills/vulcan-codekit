# `vulcan-codekit-rg`

Use this workflow when you already have a text anchor and need to find the owning structure.

Path context:

- `PWD` is an optional absolute project or workspace root. VulcanCode hides and injects it when a current project is available.
- `dir` may be relative to `PWD`; without a usable `PWD`, it must be absolute

Best for:

- log strings
- regex clues
- function or method names
- owner-context discovery

Regex behavior:

- `rg_pattern` uses ripgrep's Rust regex engine by default
- set `regex_engine = "pcre2"` only when the pattern needs PCRE2 features such as look-around or backreferences
- `extensions` is optional; when omitted, the default source-code set is exactly the list declared in `skill.yaml` for this tool
- the default source-code set excludes css, html, json, yaml/yml, hcl/tf/tfvars, and md

Typical route:

1. Start from the clue.
2. Run `rg`.
3. Use the returned owner context to decide whether `ast-detail` is needed next.

Output preserves all matching lines in the selected search scope. Indexed matches include their owning structure. Matches outside indexed AST ranges (such as top-level constants, imports, module declarations, and comments) appear under `@ Unowned matches (no indexed AST owner)` with the file path and `L<number>: <text>`. Files with no indexed symbols still return their matching lines. This group describes missing index coverage, not an AST scan failure. Extension filters and ignore rules still apply.

Lines longer than 4 KiB use match-centered previews instead of returning the entire generated or minified line. The line header explains the truncation and reports the original byte length, preview limit and complete occurrence count. Each occurrence keeps surrounding context (128 bytes per side, expanded to whole UTF-8 characters); nearby excerpts merge only while the resulting source window stays within the preview limit. Excerpts identify their original zero-based, end-exclusive UTF-8 byte ranges and covered occurrence indexes. Ellipses indicate omitted source context. If a matched span itself cannot fit together with context, its full byte range and both ends are shown with a separate explanation that its middle was omitted. Zero-width matches retain their exact byte position. No matching files, lines or occurrences are filtered out.

These presentation limits belong to `runtime/codekit-rg.lua` and must be synchronized here when they change. They do not replace the host's total-result budget: many matching lines still use host-managed paging. Original files are never changed.

The tool does not export Markdown to a caller-provided path; `export_md_path` is unsupported.

Failures return Markdown lists containing the error identifier, message, relevant paths and any nested diagnostics; they do not embed serialized JSON code blocks. Validation is unchanged: `dir` must name a directory, so passing a source-file path still reports `dir_must_be_directory`. Diagnostic paths and external messages are escaped as literal Markdown text.

AST enrichment is deliberately bounded because `rg` can match generated bundles and dependency trees that are fast to search but expensive to parse synchronously. A single file larger than 2 MiB, aggregate admitted input larger than 8 MiB, or matches beyond the first 100 admitted files skip AST enrichment. Their direct RG lines remain in the result together with an `ast_enrichment_skipped` diagnostic.

The runtime emits low-frequency `vulcan_codekit_rg` stage diagnostics for `rg_process`, `rg_parse`, `ast_plan`, each language-specific `ast_scan`, and `render`. If a call stops making progress, the last `status=started` stage identifies the blocking boundary without logging the search expression or source text.
