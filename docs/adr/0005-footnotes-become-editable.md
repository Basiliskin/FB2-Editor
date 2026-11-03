# Footnotes become editable, but only plain ones, and marks are never renumbered

Until now the bodies after the main one (footnotes) were kept as raw XML and written back unchanged, so the app could not damage them but users could not add notes either. We now read the notes body into editable Footnotes so users can insert, edit and delete them from a Note mark in the text. To keep the old "never damages a book" promise, a Footnote with anything beyond plain paragraphs (emphasis, poems, titles, extra attributes) stays read-only and its content is never rewritten, other bodies (e.g. `comments`) stay raw, and the app never renumbers marks. The user picks each label, and the next free number is filled in. An AI rewrite that drops a Note mark or points it at another note is rejected, as any changed tag already was. A Footnote that no mark points to is kept while editing, so undo still works, and dropped when the book is saved. Only notes that had a mark at some point are dropped. A note the book already had with no mark is kept.

## Considered Options

- Keep raw passthrough and only append new notes: rejected, because users could not fix a typo in a note they just added.
- Automatic renumbering: rejected, because it rewrites text the user never touched across the whole book.
