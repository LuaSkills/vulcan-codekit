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

Output focuses on matching lines and their owning structure. It does not export Markdown to a caller-provided path; `export_md_path` is unsupported.

AST enrichment is deliberately bounded because `rg` can match generated bundles and dependency trees that are fast to search but expensive to parse synchronously. A single file larger than 2 MiB, aggregate admitted input larger than 8 MiB, or matches beyond the first 100 admitted files skip AST enrichment. Their direct RG lines remain in the result together with an `ast_enrichment_skipped` diagnostic.

The runtime emits low-frequency `vulcan_codekit_rg` stage diagnostics for `rg_process`, `rg_parse`, `ast_plan`, each language-specific `ast_scan`, and `render`. If a call stops making progress, the last `status=started` stage identifies the blocking boundary without logging the search expression or source text.
