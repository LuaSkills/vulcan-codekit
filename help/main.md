# Vulcan CodeKit

Structure-aware code navigation: map a repository, find the code that owns a text clue, read exact function bodies, and replace whole functions.

## Paths

Every tool accepts an optional `PWD` project root. When the host supplies it, pass project-relative paths; otherwise pass absolute paths.

## Choosing a tool

1. Repository size, layout, or languages unknown -> `vulcan-codekit-repo-map` on the repository root.
2. Directory known, files unknown -> `vulcan-codekit-ast-tree` on exactly one directory.
3. Exact files known, structure needed -> `vulcan-codekit-ast-detail`.
4. Text clue (symbol, log string, regex) whose owning function or type matters -> `vulcan-codekit-rg`.
5. Markdown docs to triage by headings -> `vulcan-codekit-markdown-menu`.
6. Full current body of known functions or methods -> `vulcan-codekit-node-source`.
7. Replace whole functions or methods -> `vulcan-codekit-patch`.

## Rules

- Prefer CodeKit when the answer depends on function, type, or module structure. Plain search and file reads remain fine for config files, filenames, literal lookups where ownership does not matter, and tiny non-structural edits.
- Structure tools locate code; they do not prove behavior. Before claiming what code does, read its body with `vulcan-codekit-node-source` or a file read.
- In an unfamiliar repository, run Repo Map first, then narrow AST Tree and RG to the subtree it identifies instead of scanning the root again. Build this map yourself before delegating exploration.
- Read the target with `vulcan-codekit-node-source` immediately before `vulcan-codekit-patch`.
- `vulcan-codekit-patch` replaces complete function or method nodes only. Use another edit tool for partial edits, enums, struct fields, type aliases, or statements.
- `structural_path` is a slash-separated structural suffix, not a regex or glob. When a path is ambiguous, retry with the more specific path from the candidate list.
- If RG returns too many matches, narrow the pattern or directory. If Repo Map folds directories, rerun it on the relevant returned directory.

## Topics

Each tool has a help topic covering its parameters, output, and failure handling: `repo-map`, `ast-tree`, `ast-detail`, `rg`, `markdown-menu`, `node-source`, `patch`.
