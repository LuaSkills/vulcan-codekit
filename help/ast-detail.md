# `vulcan-codekit-ast-detail`

Use this workflow when you already know the exact file paths and need structural detail instead of raw text.

Path context:

- `PWD` is an optional absolute project or workspace root. VulcanCode hides and injects it when a current project is available.
- every newline-separated `paths` item may be relative to `PWD`; without a usable `PWD`, every item must be absolute

Best for:

- symbol inventories
- function and impl ownership
- file-level AST structure
- narrowing the exact edit target before patching

Typical route:

1. Confirm the file path first.
2. Run `ast-detail`.
3. Decide whether to keep reading, switch to `rg`, or move to `patch`.

Output contains the structural symbols, signatures, nesting, and line ranges needed for navigation. Runtime scan counters are compact metadata rather than part of the normal decision flow. Markdown export is not supported.
