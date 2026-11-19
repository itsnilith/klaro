# Command parity

Klaro deliberately mirrors the **interaction model** of page-based workspaces — the
same keys, the same command names, the same right-click vocabulary — so a user who has
used one already knows this one. This file is the authoritative map.

Two rules govern it:

1. **Parity is behavioural, not textual.** Nothing here is copied from another
   product's source. Every shortcut and label below is part of a public, documented
   interface convention, and every implementation in `lib/` is original code.
2. **A missing row is a bug.** If a documented command is not implemented, it is
   listed as `planned` and tracked.

## Pages

| Command | Shortcut | Status |
| --- | --- | --- |
| New page | `Ctrl+N` | implemented |
| New sub-page (inside open page) | `Ctrl+Shift+N` | implemented |
| Search pages by title | `Ctrl+P` | implemented |
| Find text in page | `Ctrl+F` | implemented |
| Duplicate page + sub-pages | `Ctrl+D` | implemented |
| Add / remove from Favorites | `Ctrl+Shift+B` | implemented |
| Rename page | right-click → Rename, `F2` | implemented |
| Add sub-page | right-click → Add sub-page | implemented |
| Move to… | right-click → Move to… | implemented |
| Move up / down | right-click → Move up / Move down | implemented |
| Change icon | right-click → Change icon | implemented |
| Add / change cover | right-click → Add cover | implemented |
| Copy page link | right-click → Copy page link | implemented |
| Export as Markdown | right-click → Export as Markdown | implemented |
| Move to Trash | right-click → Move to Trash, `Del` | implemented |
| Restore / Delete forever | Trash tab | implemented |
| Drag page onto another to nest | drag & drop | implemented |

## Inline formatting

| Command | Shortcut | Status |
| --- | --- | --- |
| Bold | `Ctrl+B` | implemented |
| Italic | `Ctrl+I` | implemented |
| Underline | `Ctrl+U` | implemented |
| Strikethrough | `Ctrl+Shift+S` | implemented |
| Inline code | `Ctrl+E` | implemented |
| Link to page | `Ctrl+K`, or type `[[Title]]` | implemented |
| Insert block menu | `Ctrl+/` | implemented |
| Slash command (typed) | `/` | implemented |

## Block editing

Blocks are rows in `note_blocks`, ordered by a fractional sibling key, so a block
keeps its identity, type and children while the page is edited.

| Command | Shortcut | Status |
| --- | --- | --- |
| Split block at caret | `Enter` | implemented |
| Soft line break inside a block | `Shift+Enter` | implemented |
| Merge into the previous block | `Backspace` at offset 0 | implemented |
| Indent / outdent a block | `Tab` / `Shift+Tab` | implemented |
| Move caret between blocks | `Up` / `Down` at block edges | implemented |
| Insert menu at the caret | `/` or `Ctrl+/` | implemented |
| Markdown block prefixes (`#`, `##`, `###`, `####`, `-`, `1.`, `[]`, `>`, ```` ``` ````) | typed at the start of a block | implemented |
| Toggle a to-do | `Ctrl+Enter` or click the box | implemented |
| Collapse a toggle | click the chevron | implemented |
| Duplicate the block and its children | `Ctrl+D` or the handle menu | implemented |
| Move a block within its siblings | `Ctrl+Shift+Up` / `Ctrl+Shift+Down` or the handle menu | implemented |
| Reorder by drag | drag the handle onto another block | implemented |
| Turn into another block type | handle menu > Turn into | implemented |
| Text and background colour | handle menu > colour | implemented |
| Delete a block | handle menu > Delete, or `Backspace` in an empty block | implemented |
| Undo / redo (text and structure) | `Ctrl+Z` / `Ctrl+Shift+Z`, `Ctrl+Y` | implemented |
| Find and replace in the page | `Ctrl+F` (bar with next, replace, replace all) | implemented |
| Bold / italic / underline / code / strike | `Ctrl+B` / `Ctrl+I` / `Ctrl+U` / `Ctrl+E` / `Ctrl+Shift+S` | implemented |
| Add a link | `Ctrl+K` (uses a URL already on the clipboard) | implemented |
| Insert an image | `/image` then pick a file | implemented |
| Insert two or three columns | `/2 col` or `/3 col` | implemented |
| Insert a table of contents | `/toc` (jumps to headings) | implemented |
| Insert a file attachment | `/file` then pick a file | implemented |
| Insert a web bookmark or embed | `/book` or `/embed`, then paste a URL | implemented |
| Change a code block language | click its language label | implemented |
| Insert a divider | `/divider`, or type `---` and press Enter | implemented |
| Insert an inline database | `/database` | implemented |
| Insert a chart bound to a database | `/chart` then Set up | implemented |
| Switch a database to the board view | table/board toggle in the database header | implemented |
| Sort a database | column menu > Sort ascending / descending | implemented |
| Filter a database | filter icon > property + value | implemented |
| Version history and restore | right-click a page > Version history | implemented |
| Save a page as a template | right-click > Save as template, or the Templates chip | implemented |
| New page from a template | right-click > New from template, or the Templates chip | implemented |
| Export as HTML | right-click > Export as HTML | implemented |
## Blocks available from the insert menu

Text, Heading 1-4, Bulleted list, Numbered list (numbered per sibling run),
To-do, Toggle (collapsible, with children), Quote, Callout, Code, Divider,
Image, Database, Chart, 2/3 columns, Table of contents, File, Web bookmark and
Embed. Any block can be nested under another with `Tab`; a toggle hides its
children when collapsed.

## Inline database

`/database` inserts a table stored in the block's props: typed properties
(text, number, select, date, checkbox), add/rename/delete properties, add and
delete rows, and a footer with per-column summaries (sum, filled, checked).
It is a single table inside the page, not yet a full collection with views,
filters, relations or rollups.

## Columns and table of contents

`/2 col` and `/3 col` create a column list with one editable block per column;
blocks can be added, edited, indented and deleted inside each column. `/toc`
lists every heading in the page (H1-H4) indented by level and scrolls to the
heading when clicked.

## Files, bookmarks and embeds

`/file` attaches any file by path, shows its name and size, opens it with the
system handler and can be removed from the card. `/book` and `/embed` store a
URL and open it in the default browser; both survive export as
`[bookmark](url)` / `[embed](url)` lines.

## Version history and templates

A version is snapshotted at most every five minutes of editing and kept for 40
versions per page; the page menu lists them with time and size and restores a
snapshot (blocks, title, icon, cover) in one action. Any page can be saved as a
template and instantiated later; template blocks are copied with fresh ids and
re-linked parents.

## Chart

`/chart` binds to a database block in the same page: choose the group column,
the aggregation (count, sum, average, min, max), the numeric value column and
bar or line rendering. The chart redraws from the table, and an empty chart
tells you what is missing instead of failing.
## Sidebar

Pages · Favorites · Trash, with counts. Search filters the tree live. The tree is
recursive; the chevron expands a page's children and drag-and-drop re-parents.

## Shortcut sheet

`Ctrl+Shift+/` opens the in-app cheat sheet. It is generated from the table above,
so the app can never advertise a binding it does not have.

## Not in scope

Klaro does not reproduce another product's application binary, bundled assets, or
source. Where a feature is not documented publicly, it is implemented from first
principles against the user's need, not reverse-engineered.