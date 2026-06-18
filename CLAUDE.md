# CLAUDE.md

## Project
A sandbox directory, not a formal app. Currently contains a single static
demo page (`index.html`) built during a Claude Code session — a hero
section plus a "how Claude Code works" explainer section, pure HTML/CSS/JS,
no build step, no dependencies.

## Structure
- `index.html` — the whole site (inline `<style>` and `<script>`, no separate
  assets). Open directly in a browser, no server needed.
- `file` — an empty test file from early in the session. Safe to ignore or delete.

## Commands
None. There's no build/test/lint pipeline — it's a single static HTML file.
To view it: `open index.html` (macOS) or just double-click it.

## Conventions
- Keep it a single self-contained HTML file unless the project grows enough
  to justify splitting out CSS/JS — don't add a build tool prematurely.
- Visual style so far: dark gradient background, monospace/terminal-flavored
  type, teal/violet/pink accent palette, glassy bordered cards for content
  sections. Match this look when adding new sections.

## Gotchas
- Not a git repository yet — there's no version history, so be careful with
  large rewrites; nothing here is recoverable via git if overwritten.

## Do NOT
- Don't introduce a framework/bundler for what is currently a one-page demo.
- Don't delete `file` or `index.html` without checking with the user first —
  this directory's contents were built interactively and may still be in use.
