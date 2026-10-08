# `vulcan-codekit-repo-map`

Start analysis of an unfamiliar repository with Repo Map. It reports repository scale, directory distribution, and code statistics for every language Tokei recognizes, so the exact `ast-tree` or `rg` directory scope can be chosen afterwards.

## When to use

- First contact with a repository whose size and structure are unknown.
- The source directory for `ast-tree.dir` is not known yet.
- The subtree that `rg.dir` should be narrowed to is not known yet.
- Monorepos, generated directories, configuration-heavy directories, or code hotspots need to be identified.
- "The repository has no files" must be told apart from "Tokei does not recognize these files".

## Input

- `PWD`: optional absolute project or workspace root. VulcanCode hides and injects it when a current project is available; `dir` may then be relative to it. Other hosts may pass it explicitly; without a usable `PWD`, `dir` must be absolute.
- `dir`: required. Exactly one existing repository or directory path; files, multiple paths, and newline-separated lists are rejected.
- `max_depth`: optional, default `3`, range `1..8`. Controls only the depth of the model-visible directory tree; the whole directory is always scanned and aggregated recursively first.
- `noignore`: optional, default `false`. `true` disables ordinary `.gitignore`, `.ignore`, and `.tokeignore` rules; directories that CodeKit always excludes, such as `.git`, `target`, `node_modules`, and `dist`, are still never scanned.

Repo Map deliberately has no `extensions`, `languages`, or Tokei `types` parameter. Its job is a complete repository-level first map, not an early guess about which languages matter.

## Output

Plain Markdown with these sections:

1. `OVERVIEW`
   - Total directory count.
   - Total regular file count.
   - Files recognized by Tokei.
   - Files not recognized by Tokei.
   - Total file bytes.
   - Code, comment, blank, and total line counts.
   - The effective ignore, hidden-file, symlink, and folding settings.
2. `LANGUAGES`
   - Every primary language Tokei detected.
   - Files, code, comments, blanks, and total lines per language.
   - Tokei's inaccuracy markers.
3. `DIRECTORY TREE`
   - Directory nodes only, never file nodes.
   - Each directory shows direct and recursive subdirectory counts and direct and recursive file counts.
   - Each directory shows recursive recognized/unrecognized files, bytes, code lines, and its main languages.
   - Nodes beyond the depth or node limit show `folded:N`; parent and repository totals still include the folded subtrees.
4. `DIAGNOSTICS`
   - Present only when traversal errors, metadata read failures, or other incomplete states occurred.

## Counting rules

- `Files` counts every regular file after ignore rules and hard exclusions; it is not the number of source files.
- `Recognized files` is the number of unique files Tokei actually reported.
- `Unrecognized files` is the difference between the full file census and the Tokei report set.
- `Lines` equals Tokei's `code + comments + blanks`; unrecognized files add no code lines but still add files and bytes.
- Embedded-language blocks are folded into their host file through Tokei `CodeStats::summarise`, so they are neither missed nor double counted.
- A directory's `files:A/B` means direct files / recursive files.
- A directory's `dirs:A/B` means direct subdirectories / recursive descendant directories, excluding the directory itself.
- The root is `.` and paths always use `/`, so platform separators never enter the stable output format.

## Default safety boundaries

- Hidden but legitimate directories such as `.github` are included.
- `.gitignore`, `.ignore`, `.tokeignore`, and parent ignore files are honored by default.
- Symbolic links are never followed.
- `.git`, `target`, `node_modules`, `dist`, `build`, `vendor`, `output`, `.idea`, `.vscode`, and `__pycache__` are always excluded.
- Full-repository scans in one host process run one at a time, so concurrent Repo Map calls do not compete for disk and CPU.
- Display trimming happens only after full aggregation; a shallow scan is never presented as complete repository statistics.

## Recommended workflow

1. `vulcan-codekit-repo-map`: understand total scale, directory and language distribution, and code hotspots.
2. `vulcan-codekit-ast-tree`: build a per-file AST summary of one source directory selected from Repo Map.
3. `vulcan-codekit-ast-detail`: expand the structure of files that are already known.
4. `vulcan-codekit-rg`: map text anchors to their owning function, method, or type inside the narrowed directory.
5. `vulcan-codekit-node-source`: read the full current source of known functions or methods.
6. `vulcan-codekit-patch`: replace confirmed whole functions or methods structurally.

## Misuse to avoid

- Repo Map is not a file finder; it never returns file names.
- Do not keep raising `max_depth` to find a known symbol; use `rg` for a known text anchor.
- An unrecognized file count does not mean files are missing; Tokei simply produced no code statistics for them.
- Do not use `noignore=true` by default; use it only with a concrete reason to inspect ignored directories.
- Once Repo Map has pointed to a specific source subtree, do not run a broad `ast-tree` on the repository root.
