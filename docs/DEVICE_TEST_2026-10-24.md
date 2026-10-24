# Device test — 2026-10-24

Build: 1.5.2 (26), release, R8 shrinking on, signed with the upload key.
Device: Samsung SM-S711B. Book: «Последняя Капля» (32 chapters, 1.3 MB, PNG cover).
Logs were recorded for the whole session: no app errors or crashes.

## Works

- Open a book from storage; Info and Book tabs.
- Chapter editor: typing, undo, insert image from gallery.
- Story map, AI prompt with no provider set up, Find (and replace dialog), Settings.
- New section (an empty name is ignored).
- Save in the app; export FB2, EPUB, TXT. Exported FB2 matches the source
  (32 sections, annotation and cover kept).

## Bugs

1. **Swipe deletes a chapter with no confirmation or undo.**
   `lib/widgets/section/list.dart:119`: the `Dismissible` removes the section on
   `onDismissed`. One accidental swipe while scrolling loses a whole chapter on the next save.
   Fix: `confirmDismiss` dialog, or a SnackBar with Undo.
   **Fixed:** a swipe now asks "Delete section?" first; Cancel puts the card back.

2. **Re-exporting gives a broken file name.** Exporting FB2 a second time to the
   same folder saved `Кац Дмитрий - Последняя Капля.fb2 (1)`, so the file no
   longer ends in `.fb2` and readers don't open it. `FlutterFileDialog.saveFile` is called
   with `mimeTypesFilter=null` (logcat), so the system picker treats the file as `*/*` and
   appends " (1)" after the extension. Fix: pass the MIME type
   (`application/x-fictionbook+xml`, `application/epub+zip`, `text/plain`) in
   `SaveFileDialogParams` (`lib/services/app.service.dart`, `exportProject`, `exportText`,
   `exportEpub`).
   **Fixed** for EPUB and TXT: the picker now gets the MIME type and names a repeat
   `name (1).epub`. FB2 stays as it is: Android's MIME tables (`framework.jar`
   `res/*.mime.types`) have no `.fb2` entry, so its storage provider still adds " (1)"
   after the extension. The FB2 export passes `application/x-fictionbook+xml` anyway.

3. **EPUB cover declared with the wrong type.** The source FB2 says
   `<binary content-type="image/jpeg" id="cover.jpeg">` but the data is PNG. The EPUB
   carries this over: `OEBPS/images/cover.jpeg.png` is listed as `media-type="image/jpeg"`
   in `content.opf`. Strict readers and epubcheck reject this. Fix: when building the EPUB,
   detect the real type with `sniffBase64ImageType`, as the cover picker already does.
   **Fixed:** the EPUB now declares each picture by its bytes (`image/png` here); a declared
   type is kept only when the bytes are not PNG, GIF, WebP or JPEG.

4. **"Unsaved changes" shown when nothing changed.** I typed, undid it, inserted an
   image, deleted it, then chose "Don't save" when leaving the editor. The export sheet
   still showed "Unsaved changes", and leaving the book asked to save again. The exported
   FB2 was identical to the saved one, so the indicator was wrong.
   Cause: the indicator was right. "Don't save" left the edits in memory (exporting saves
   first, which is why the export matched). **Fixed:** the chapter editor takes a copy of the
   chapter and the book's pictures when it opens and puts it back on "Don't save".
   Leaving the book screen with "Don't save" still keeps its edits in memory until the
   book is opened again.

## Rough spots

- Deleting an image in the editor happens at once, with no confirmation, and Undo is
  greyed out after inserting an image, so neither action can be undone.
- Switching Info → Book shows the "Saved in the app" SnackBar every time.
- Story map lists inflected name forms as people: «Сайласа», «Капитана», «Брота»,
  «Корвуса» instead of nominative forms.
- The image picker allows choosing several photos, although only one is inserted.

## Not app bugs (source file)

- Chapter 1's first paragraph repeats the heading ("Глава 1: Последняя Капля Тусклый…").
- The text contains literal Markdown `*asterisks*`.

## Not tested

- AI improve with a real provider; Replace all; Add another book (merge); deleting a
  book from the library; cover change.
