# `vulcan-codekit-markdown-menu`

Use this workflow when the right Markdown document or heading is still unknown.

Path context:

- `PWD` is an optional absolute project or workspace root. VulcanCode hides and injects it when a current project is available.
- every newline-separated `path` item may be relative to `PWD`; the omitted-path default `.` means that root
- without a usable `PWD`, every path must be absolute

Best for:

- doc triage
- heading-only navigation
- locating the correct section before opening body text

Keep the first pass shallow and non-recursive unless you already know the docs subtree is the right one.

Output focuses on file names, headings, levels, and line numbers. Scan counters and overflow details are runtime metadata, not required navigation input.
