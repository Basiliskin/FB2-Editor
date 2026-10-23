# User feedback issues (Google Play reviews)

Source: all 120 Play Console reviews, read 2026-10-23 (rating 2.42, 177 ratings). Mostly versions
1.0.1 – 1.0.4; current is 1.1.1+19, so every item needs a re-check against the current build.
`[code]` = confirmed by reading the code. `[review]` = taken from reviews only, not yet reproduced.
Line numbers refer to the repo at commit `6ad7dac`.

## Summary

| # | Issue | Severity | Reviews | Status |
|---|---|---|---|---|
| 1 | Save drops FB2 content (footnotes, extra images, other bodies) | Critical | ~6 | [code] |
| 2 | Saved file has no `<book-title>`: reader shows "Untitled" | Critical | ~4 | [code] |
| 3 | Metadata written in invalid order/elements: genre, series, year lost in strict readers | High | ~3 | [code] |
| 4 | Endless loading or failure to open (large, damaged, non-FB2 files) | High | ~25 | [review] |
| 5 | Saved changes do not appear / unclear save location / two-step save | High | ~10 | [review] |
| 6 | Text vanishes or formatting loses work (indents, highlight, chapter starts) | High | ~5 | [review] |
| 7 | Large sections are split and renamed on load (`Title - 500`) | Medium | 1+ | [code] |
| 8 | Cover quality and fit | Medium | ~4 | [review] |
| 9 | Inserting images into text does not work or is not discoverable | Medium | ~8 | [review] |
| 10 | id/version/lang/translator fields not saved or not editable | Medium | 2 | [code] |
| 11 | Missing: create new book, find and replace, poem/verse, TOC, merge, formats | Feature | ~15 | |
| 12 | Discoverability, naming, help, store listing | Low | ~6 | |

---

## 1. Save drops FB2 content (footnotes, extra images, other bodies) — Critical [code]

**Reviews:** "after changing the cover the footnotes stopped working and the illustrations
disappeared" (Jul 2026); "first image appears double"; "editor only saw the captions" for
illustrated books; "entire file structure is messed up" when reopened in FBE on Windows.

**Cause.**
- `lib/models/project.model.dart:429-433` writes exactly one `<body>` containing the book title and
  the sections. Every other `<body>` (notably `<body name="notes">`, which footnote links point to)
  is never parsed or written. `lib/services/fb2.service.dart` also reads only `body.first`.
- `lib/models/section.model.dart:34-39` writes one `<image>` per section; `project.model.dart:162-166`
  keeps only the first image (`sublist(0, 1)`).
- `lib/utils/common.dart:310-313` reads only the top-level `<section>` children of the first body;
  nested sections, poems, epigraphs and tables are only kept if `parseXml` happens to pass them
  through as strings (verify with the fixture below).

**Reproduce.**
1. Take an FB2 with a `<body name="notes">` and `<a l:href="#n1" type="note">`, two `<image>` tags in one
   section, a `<poem>`, and a nested `<section>`.
2. Open it in the app, change only the cover, save.
3. Diff the output: notes body gone, second image gone, nested content flattened or gone.

**Fix.**
1. Add a failing round-trip test first: parse → `getBookXml()` → parse again, assert every `<body>`,
   `<image>`, `<poem>`, `<a type="note">` and nested `<section>` survives (`test/` already has coverage
   tooling).
2. Parse all `<body>` elements; keep non-main bodies as raw XML strings on `ProjectModel` and write
   them back unchanged.
3. Store all section images, not only the first (`images` is already a list; remove the `sublist(0, 1)`
   and write every image at its original position, not just first).
4. Preserve unknown section children as opaque raw XML blocks and write them back in order.
5. Safety net: before the first overwrite of a user file, copy the original to `<name>.fb2.bak`.

---

## 2. No `<book-title>` in saved file: reader shows "Untitled" — Critical [code]

**Reviews:** "after changing the cover the book title disappears, reader shows Untitled" (Jun 2023);
"resulting book has no genre, no series, no title, no publication year" (Sep 2024); "the title
doesn't fit" (Oct 2025).

**Cause.** `getBookXml()` (`project.model.dart:386-433`) writes the title only as `<body><title>`.
`<book-title>` inside `<title-info>` is never emitted (`grep book-title` finds only the read side at
line 232). Readers take the library title from `<book-title>`.

**Reproduce.** Open any FB2, save without edits, open the result in a reader or FBReader: title is
"Untitled" / file name.

**Fix.** Emit `<book-title>$bookTitle</book-title>` in `title-info`. Escape XML text for all
interpolated values (see issue 3). Add a test asserting `book-title` equals the edited title.

---

## 3. Metadata written in invalid order and with invalid elements — High [code]

**Reviews:** genre, series and year missing after editing metadata; "the file doesn't open in the
reader" after cover change; FBE on Windows reports a broken structure.

**Cause (`project.model.dart:386-430`).**
- Element order in `title-info` is genre, sequence, annotation, coverpage, author. The FB2 schema
  requires genre, author, book-title, annotation, date, coverpage, lang, sequence. Strict readers
  drop or reject out-of-order elements.
- `<fb-editor>1</fb-editor>` is not an FB2 element and is written inside `title-info`.
- `date` and `lang` are parsed from `title-info` (lines 224-225) but written only inside
  `document-info`, where `lang` is invalid, so the year is lost.
- Genre, series, title and annotation text are interpolated with no XML escaping: `&`, `<` in a title
  or annotation produce invalid XML.
- Line 410 `print(xml.join())` dumps the whole book to the log on every save.

**Reproduce.** Edit series and genre, save, open in FBE or run `xmllint --schema FictionBook.xsd`.

**Fix.** Rewrite `title-info` in schema order, write `book-title`, `date`, `lang` there, drop
`fb-editor`, escape all text (`XmlText`/`XmlBuilder` instead of string concatenation, which the `xml`
package already provides), remove `print`. Validate output against the FB2 XSD in a test.

---

## 4. Endless loading / cannot open files — High [review] — partly fixed

**Reviews (~25):** "waited 12 minutes" (Jun 2026); "endless loading", "half an hour", "doesn't load
books"; "doesn't read even a 1.2 MB file"; "didn't work with the 6 MB book"; "txt file → eternal
loading"; "opens a blank book after restart"; "can't open a properly modified file"; "froze after a
small jokes book".

**Likely causes (to confirm).**
- `fb2.service.dart:_tryParseSync` repairs malformed XML by dropping one character per retry and
  re-parsing the whole string: up to 100 full re-parses, each O(n).
- `xml2json` conversion of the full description and sections on the isolate, then everything held in
  memory as strings.
- No timeout, no progress, no cancel, and no error state when `_convertXml` returns null.
- Non-FB2 input (txt, epub) is not rejected up front.

**Reproduce.**
1. Generate an FB2 with 6–20 MB of text and thousands of `<p>`; time the open.
2. Pick a `.txt` and an `.epub` file; the spinner never ends.
3. Pick an FB2 with a stray `&` and one with CP1251 encoding and no XML declaration.

**Profile (desktop JIT, synthetic books, 2026-10-23).** Clean files are not slow: 6 MB in 0.5 s,
20 MB in 1.7 s end to end. The slow path was malformed XML: 100 stray `<` in 12 MB took 4.6 s
(vs 1.0 s clean) because every repair re-parsed the book, and 300 stray characters failed outright at the
100-repair cap, with no message. On a phone ~20x slower that is minutes. Cover decoding already
uses the native codec off the UI thread.

**Done:** one-pass `sanitizeXml` before the per-character fallback (12 MB with 300 stray `<`: 1.3 s);
`parseTimeout` (90 s + 10 s per MB) so a hung parse ends; typed `OpenFailure` with English and Russian
messages for unsupported type, unreadable file, zip without a book, not-FB2 and timeout; cancelling
the picker no longer shows an error. **Not done:** progress/cancel button, TXT import, blank-book
detection, killing the isolate after a timeout (it keeps running until it finishes).

**Original plan.**
1. Profile with the large fixture first; add a timing test.
2. Replace repair-by-retry with one pass (pre-escape bare `&`, strip invalid chars with a regex) and a
   hard limit; keep retry only as a fallback.
3. Reject by extension/magic bytes: show "not an FB2 or ZIP" for others (reviews also ask for EPUB:
   see issue 11).
4. Always end loading with either a book or a readable error; add timeout, cancel button and progress.
5. Show a precise error for empty/blank results instead of an empty book ("blank file" review).

---

## 5. Saved changes do not show up / unclear where files go — High [code] — fixed

**Reviews:** "edit, save, close/open — no changes"; "doesn't save changes" (x4);
"you need to save twice: floppy icon to the internal image, then stack icon to a file";
"unclear where the file is saved; can't choose a path"; "deleted text in the editor, reader shows
nothing changed, editor shows it fine".

**Confirmed in the code (before the fix).** `exportProject` handed the dialog the stored app copy
without saving first, so an export from the section editor skipped the paragraph being edited and any
unsaved change. The exported file was named `<random id>.fb2`. A cancelled dialog still showed
"Saved ... null". Leaving the editor with auto-save off silently kept nothing.

**Done:** export saves first (and the editor commits the open paragraph first); file named
"Author - Title.fb2"; no message on cancel, the path on success; "Saved in the app. Use Export..."
wording; leaving the editor or book with unsaved changes asks Save / Don't save / Cancel (silent save
when auto-save is on); the system back gesture goes through the same check; help text explains reader
caching. **Not done:** a single combined Save button, choosing the folder in settings, a `.bak` copy
(the app never overwrites the original: it works on a private copy and exports to a new file, so it
is not needed).

**Cause.** There are two separate saves: one into the app's private workspace and one export to a
user file. The first looks like a complete save. Readers keep their own cached copy of the book, so
an exported file with the same path can look unchanged.

**Reproduce.** Edit a chapter, tap the floppy icon only, then look for the changed file in the file
manager: unchanged.

**Fix.**
1. One primary "Save" that does both, or an unsaved-changes badge and a prompt on exit.
2. After export show the full path/URI and an "Open folder / Share" action.
3. Offer "Save as copy" and "Overwrite original" choices; use the Storage Access Framework picker so
   the user chooses the folder.
4. In help text, mention that readers cache books and need the old entry removed (a reviewer did this
   by hand).

---

## 6. Text vanishes or formatting destroys work — High [code] — fixed

**Reviews:** "text disappearing from chapters, about 20 percent of the end remains" (May 2024);
"all work lost when using highlight, italics, indentation" (Mar 2023); "constantly removes indents"
(Mar 2025); "text that wasn't highlighted is still highlighted after saving" (May 2023);
"deleting author notes at chapter ends, reader shows nothing changed".

**Confirmed and fixed (2026-10-23).**
- Editing any paragraph that contained inline markup (bold, italic, a footnote link) split it into
  one paragraph per child: `<p>one <strong>two</strong> three</p>` became `Xone `, a paragraph
  holding only the bold word, and ` three`. The editor now shows a paragraph as one line of inline
  markup and writes it back as one paragraph (`Section.editableText` / `replaceParagraph`).
- Typed `&` or `<` was stored raw and made the paragraph invalid XML; pasted text had the same
  problem. Typed text is now made safe (stray `&`/`<` escaped, unparseable lines kept as plain
  text) and pasted text is escaped completely.
- Editing a poem, table or other block turned it into a `<p>` holding the block. Blocks are now
  edited as whole XML and an edit that breaks them is ignored.
- Loading deleted literal backslash sequences (`C:\temp\new` became `C:empew`) and glued lines
  that were wrapped inside a paragraph (`one\ntwo` became `onetwo`). Both are fixed.
- A random edit test (`test/widgets/section_editor_property_test.dart`: activate, type, split, save
  over 80 steps, three seeds) fails on the old editor and passes now.
- Highlight and indent buttons no longer exist in the toolbar (only undo/redo, bold, italic, quote
  and paste tools), so those reports are from 1.0.4 and no longer apply. Indents made of spaces or
  no-break spaces are kept (tested). Tab characters are kept as well.

**Not reproduced:** "about 20 percent of the end of the chapter remains" (May 2024, v1.0.4). The
random edit test finds no loss in the current editor; it was probably the old chunking (issue 7) or
the old per-child split above.

**Original analysis.**
**Likely causes.**
- Editing works on ranges of paragraphs (`Section.loadRange`) and `_editContent` rewrites paragraph XML
  for bold/italic/quote; an off-by-one in a range (especially across the 500-paragraph split, see issue 7)
  would drop paragraphs.
- Indents: FB2 has no indent attribute; the app's indent is Quill-only and not serialised, so it is
  stripped on save by design. The `parseP` conversion also discards inline formatting (the delta mapping
  is commented out in `section.model.dart`), so highlight state does not round-trip.

**Reproduce.** Section with >500 paragraphs: select across the 500 boundary, apply italic, save, compare
paragraph counts. For indents: indent a paragraph, save, reopen.

**Fix.** Property test: random edit sequences must never reduce the paragraph count except for deleted
text. Either serialise indent as the FB2 convention (leading `&#160;` or a `<p>` style) or hide the
indent control. Keep an undo snapshot per section before each range rewrite.

---

## 7. Big sections are split and renamed on load — Medium [code] — fixed

**Cause.** `project.model.dart:179-206` splits any section with more than `MAX_SECTION_LENGTH = 500`
paragraphs into several `Section`s titled `"$title - $i"`, all with the **same `sectionId`**. They are
then saved as separate sections, so the book structure changes silently, ids collide, and images attach
to every chunk (a probable cause of the "first image appears double" review; unverified).

**Done:** the split is removed (it dates from when the editor laid out a whole section eagerly; the
editor now pages paragraphs and has a 5000-paragraph scroll test). A second loss in the same
function is fixed too: sections with no paragraphs were dropped on load, so a "New section" that
was still empty, a title-only part heading, or a picture-only section vanished after save and
reopen. Sections are now dropped only when they have no title, text or picture. Covered by
`test/services/fb2_roundtrip_test.dart`. Issue 6's "end of the chapter remains" report is not
explained by this and still needs a reproduction.

**Reproduce (before the fix).** Open a book with a 1200-paragraph chapter, save without edits: three sections
`Chapter - 0`, `Chapter - 500`, `Chapter - 1000`, each with the chapter image.

**Fix.** Page inside the editor (the new `loadRange` already enables this) and keep one `Section` per
original section. If splitting must stay, generate unique ids, only give the image to the first chunk
and merge chunks again on save.

---

## 8. Cover quality and fit — Medium [review] — fixed

**Reviews:** "new cover is ALWAYS much lower quality than what you add"; "cover doesn't fit";
"cover doesn't change"; "only the cover was saved, the book stayed the same"; "set a cover, nothing
changed in the reader" (readers cache covers).

**Cause.** Covers are re-encoded as JPEG with `image` and the content type is hard-coded
`image/jpeg` / `.png` id mix (`project.model.dart:355-366`: id built as `"<rand>.png"` and later
`"#${json["id"]}.png"` gives `.png.png`).

**Reproduce.** Pick a 3000×4000 PNG as the cover, save, inspect `<binary>` id, content type and size.

**Fix.** Keep the original bytes when already JPEG/PNG and under a size cap, otherwise resize with a
quality setting; set the correct content type and a clean id; add crop/fit preview; test that the
`<coverpage>` href matches a `<binary id>`.

**Status.** Fixed: the content type and id extension come from the image's first bytes (PNG, GIF,
WebP, JPEG); `coverpage.href` always equals the `<binary id>`; saving without touching the cover keeps
its id and bytes, a new picture gets a new id (readers cache by id); resizing never enlarges a small
picture; the cover preview shows the whole image (`contain`) instead of cropping it. Not done: a
crop tool, and the default setting "best" already keeps the original bytes, so the "lower quality"
reports most likely came from a lowered quality/width setting or from the upscaling above.

---

## 9. Inserting images into text — Medium [review] — fixed

**Reviews (~8):** "pick an image, it never appears"; "how do I insert pictures?"; "can't insert
multiple images into one section"; "I insert a picture, upload the book, there's no picture".

**Cause.** The data model is one image per section placed before the text (`Section.images`,
`setImage`); there is no inline image embed in the editor. The "book" button the earlier reviews
complained about was the section-image picker.

**Fix.** Support inline `<image>` blocks in the editor (Quill image embed ↔ `<image l:href>`), allow
multiple images per section, and label the existing section-image button as "Section picture".
Depends on issue 1 (multi-image serialisation).

**Status.** Fixed: pictures are now blocks inside the section, kept in their original position on
open and save; the editor shows them between paragraphs with a delete button; the image button in the
toolbar picks a file and inserts it after the paragraph being edited (or at the end), any number per
section; the content type comes from the file. The old corner thumbnail and its "show page image"
setting are gone. Not done: pictures inside a paragraph (inline in a line of text) and moving a
picture up or down.

---

## 10. id / version / lang / translator and other tags — Medium [code] — fixed

**Reviews:** "changes to id and version fields aren't saved"; "more description sections (language,
translator, email)"; "annotation pasted from the clipboard can't be edited afterwards".

**Cause.** `ProjectModel.update` (`project.model.dart:~345-380`) copies only title, authors, genre,
series, annotation and cover; `id` and `version` are read but never updated from the form. There are
no inputs for language, translator, publisher, date, keywords.

**Fix.** Extend `ProjectModel.update` and `book_form.dart` with language, date, translator, id,
version, keywords; support multiple authors; make the annotation fully editable (multi-paragraph).

**Status.** Fixed: the form edits id, version, language, written date, keywords and the author's
e-mail, and they are saved and reloaded. Also found and fixed on the way: saving dropped every
second author, the translator, `src-lang`, publisher, history, `publish-info` and `custom-info`;
the document's scanner author was replaced by the book author; the book's author got the document
id written into its `<id>`; empty `<middle-name>`/`<nickname>`/... elements were written. These parts
are now carried through unchanged and written in schema order. Not done: editing the translator or a
second author in the app (they are preserved but have no form), and annotation with inline markup.

---

## 11. Missing features asked for — done except EPUB and a table of contents

| Request | Reviews | Notes |
|---|---|---|
| Create a new empty book | ~6 (Apr 2024, Dec 2022, Nov 2022 and others) | Add "New book" on the library screen; template with empty `title-info`. |
| Find and replace | 4 (Apr 2025, Apr 2024, Apr 2022…) | Search across sections, replace one/all. |
| Poem / verse | 1 | `<poem><stanza><v>` support. |
| Table of contents | 1 | Generate a TOC from sections, or explain that FB2 readers build it. |
| Merge books (series into one file) | 1 | Combine bodies/sections, merge binaries with unique ids. |
| Other formats (EPUB, TXT), import txt | 3 | Import TXT as a section; EPUB import/export as a later step. |
| Font size and margins in editor | 1 | Settings screen. |
| Paste text from the clipboard | 1 | Exists via the book button; make it discoverable. |
| Insert/remove "Red Book" button | 5 (2021–22) | Already fixed in 1.0.2+, the toggle exists. |
| Sell/upload books | 1 | Out of scope. |

**Status.**
- *Create a new book* — done: a "New book" tile in the library creates a valid FB2 (title, one empty
  chapter, generated id) and opens it. The editor got an "Add paragraph" button at the end of every
  section, which was also missing for empty sections (a new section could not be typed into at all).
  An added paragraph left empty is dropped on save.
- *Find and replace* — done: a search icon on the book page opens a sheet that searches every
  paragraph and section title, shows snippets, replaces one hit or all, optional match case. It only
  touches text, never tags, attributes, links or pictures. Limits: a match split across two styles
  (half in bold) is not found; titles of the book itself and the annotation are not searched.
- *Paste text from the clipboard* — already existed (book button); the help text covers it.
- *Poems* — done: a toolbar button turns the copied text into a poem (blank line = new stanza)
  after the paragraph being edited; plain poems are shown as verses and edited as lines of text;
  a poem with a title, author, date or styled verses is still edited as XML so nothing is lost.
- *TXT* — import done: a .txt file (UTF-8 or Windows-1251) opens as a new book named after the file;
  short lines starting "Chapter/Part/Prologue/Глава/Часть/Пролог…" start new sections. Export done:
  "Export as text (.txt)" in the book page's More menu.
- *Merge books* — done: "Add another book" (More menu) appends the chapters of an .fb2/.zip/.txt
  after a heading section named after it, with its pictures and footnotes under prefixed ids so
  nothing clashes; this book's cover and metadata stay. Note: the picked file is copied into the
  app folder by the existing open path and not removed.
- *Editor margins* — done: Settings → "Page margins" (8–56). Font size already existed.
- *Table of contents* — not built: FB2 readers generate it from section titles, so a hand-made
  contents section would duplicate it and go stale. Say so in the store listing (issue 12).
- *EPUB import/export* — not done: it needs an HTML/CSS to FB2 converter (and back) and is a project
  of its own.

---

## 12. Discoverability, naming, listing — Low

- "Name should be FB2 *information* editor": the store title oversells text editing (Jul 2025). Clarify
  the listing: covers, metadata, chapter editing.
- "How do I edit the book contents? No button" (Mar 2025); "unlabeled toolbar icons", "no help": the
  Help page exists now, so link it from the first screen and add tooltips to toolbar icons.
- Old permission complaint (Jul 2023, 16 helpful votes): the current manifest declares only
  `AD_ID`; confirm no media permission is requested at runtime (`permission_handler` is a dependency).
- "Not in Russian" (2021–22): fixed by the RU/EN setting; the listing should say so.
- Positive notes to protect: cover editing is the main reason for 5★ reviews ("saved my life",
  "only app on the Play Store"); keep that flow fast and lossless.

### Status

- *Permission*: `start_page.dart` asked for `Permission.storage` on every launch, although the manifest
  declares no storage permission (so Android never showed a dialog). The call and the
  `permission_handler` dependency are removed; files come from the system picker. A test pins the
  release manifest to `AD_ID` only. The old review can be answered with this.
- *Help*: the library screen has had a Help icon since issue 5; the editor app bar has one too.
- *Tooltips*: editor toolbar buttons (undo, redo, bold, italic, quote, picture, poem, new section,
  annotation) now have EN/RU tooltips. The stock rich-text buttons are not on the toolbar.
- *Start screen*: the delayed init is a cancellable `Timer`, so it no longer runs after the screen is gone.
- *Store listing*: not changed here (it is edited in Play Console, see `docs/RELEASE.md`). Suggested
  wording for the next listing update:
  - Title: "FB2 Editor: covers & metadata" (keeps FB2 searchable, says what it is good at).
  - Short description: "Edit FB2 e-books: cover, title, author, chapters, pictures, poems. English and Russian."
  - Full description should say: opens .fb2, .fb2.zip and .txt; edits cover, metadata, text and
    pictures; find and replace; merge books; exports .fb2 and .txt; no table of contents (readers build
    it from chapter titles); no EPUB.
  - Reply to the Jul 2023 permission review and the Jul 2025 naming review after the release.

---

## Suggested order of work

1. Round-trip fixture and tests (issues 1–3, 7), then fix the serializer. This removes most data loss.
2. Open-path hardening: timeouts, errors, big-file profile (issue 4).
3. Save UX (issue 5) and the `.bak` safety copy.
4. Editor integrity (issue 6) and inline images (issue 9).
5. Features: new book, find and replace, metadata fields (issues 10–11).
6. Store listing and in-app help (issue 12); reply to old reviews once fixed.
