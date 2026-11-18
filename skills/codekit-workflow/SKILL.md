---
name: codekit-workflow
description: "Use this guide for repository maps, owner-aware search, exact source extraction, or whole-function edits."
---

# Vulcan CodeKit

Use the direct tool when it is registered individually. For an entry set to implicit, read this guide with `skill` and use `tool_call` with `skill` set to `luaskills-vulcan-codekit:codekit-workflow`, `action` set to the public tool name, and `arguments` set to the entry's JSON object.

Structure-aware code navigation: map a repository, find the code that owns a text clue, read exact function bodies, and replace whole functions.

## Paths

Every tool accepts an optional `PWD` project root. When the host supplies it, pass project-relative paths; otherwise pass absolute paths.

## Choosing a tool

1. Repository size, layout, or languages unknown -> `vulcan_codekit_repo_map` on the repository root.
2. Directory known, files unknown -> `vulcan_codekit_ast_tree` on exactly one directory.
3. Exact files known, structure needed -> `vulcan_codekit_ast_detail`.
4. Text clue (symbol, log string, regex) whose owning function or type matters -> `vulcan_codekit_rg`.
5. Markdown docs to triage by headings -> `vulcan_codekit_markdown_menu`.
6. Full current body of known functions or methods -> `vulcan_codekit_node_source`.
7. Replace whole functions or methods -> `vulcan_codekit_patch`.

## Rules

- Prefer CodeKit when the answer depends on function, type, or module structure. Plain search and file reads remain fine for config files, filenames, literal lookups where ownership does not matter, and tiny non-structural edits.
- Structure tools locate code; they do not prove behavior. Before claiming what code does, read its body with `vulcan_codekit_node_source` or a file read.
- In an unfamiliar repository, run Repo Map first, then narrow AST Tree and RG to the subtree it identifies instead of scanning the root again. Build this map yourself before delegating exploration.
- Read the target with `vulcan_codekit_node_source` immediately before `vulcan_codekit_patch`.
- `vulcan_codekit_patch` replaces complete function or method nodes only. Use another edit tool for partial edits, enums, struct fields, type aliases, or statements.
- `structural_path` is a slash-separated structural suffix, not a regex or glob. When a path is ambiguous, retry with the more specific path from the candidate list.
- If RG returns too many matches, narrow the pattern or directory. If Repo Map folds directories, rerun it on the relevant returned directory.

## References

- [ast-detail](references/ast-detail.md)
- [ast-tree](references/ast-tree.md)
- [markdown-menu](references/markdown-menu.md)
- [node-source](references/node-source.md)
- [patch](references/patch.md)
- [repo-map](references/repo-map.md)
- [rg](references/rg.md)
