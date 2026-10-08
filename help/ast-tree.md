# `vulcan-codekit-ast-tree`

Use this workflow after Repo Map has identified the source directory to inspect. If the repository or source scope is still unfamiliar, run `vulcan-codekit-repo-map` first.

Path context:

- `PWD` is an optional absolute project or workspace root. VulcanCode hides and injects it when a current project is available.
- `dir` may be relative to `PWD`; without a usable `PWD`, it must be absolute

Best for:

- building a per-file AST map inside one selected source directory
- choosing candidate files
- identifying the heavy modules before deep reads

Typical route:

1. Run `ast-tree` with `dir` set to the most relevant directory.
2. Pick candidate files from the grouped output.
3. Follow with `ast-detail` or `rg` on a narrower target.

Input notes:

- `dir` must be exactly one existing directory path
- files, newline-separated path lists, and multiple directories are rejected
- `extensions` is optional; when omitted, the default source-code set is exactly the list declared in `skill.yaml` for this tool
- the default source-code set excludes css, html, json, yaml/yml, hcl/tf/tfvars, and md
