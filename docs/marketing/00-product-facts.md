# Product Facts

> Single source of truth for all downstream marketing skills. No promotional material may claim more
> than this document supports.

## Verified facts

Every fact traced to a repository file, the README, or the user. The `source:` field is restricted to
`<repo-relative path>` | `README` | `user`.

- FB2 Editor is a fiction-book editor for the FB2 (FictionBook 2) format — source: pubspec.yaml
- Built with Flutter (Dart SDK >=3.0.0), using the flutter_quill rich-text editor (v11.5.0) — source: pubspec.yaml
- README describes the project as "FB2 Editor — Writen with flutter" (self-published, minimal) — source: README
- Ships as an Android app: applicationId `com.caragulak.fb2editor`, target/compile SDK 35, version 1.0.4+15 — source: android/app/build.gradle
- Reads FB2 files by parsing the FictionBook XML (`description`, `body`, `binary` resources) — source: lib/services/fb2.service.dart
- Parses malformed FB2 XML leniently: on a parse error it removes the offending node and retries, so damaged books still open — source: lib/services/fb2.service.dart
- Decodes legacy Windows-1251 (Cyrillic) text from book files — source: lib/utils/cp1251.dart
- Opens both `.fb2` and `.zip` files from device storage via the system file picker — source: lib/services/app.service.dart
- Sections are edited in a Quill rich-text editor with a toolbar offering headers, bold/italic, links, text/background color, lists, checklists, indentation, clear formatting, undo/redo, and image insertion — source: lib/widgets/section_editor/toolbar.dart
- Rich-text formatting round-trips into FB2 XML tags on save: bold → `<strong>`, italic → `<emphasis>`, blockquote → `<cite>` — source: lib/services/app.service.dart
- Per-section images are picked from the device (image_picker) and embedded in the FB2 file as base64 `<binary>` resources — source: lib/models/project.model.dart
- Sections can be created, marked and batch-deleted, drag-reordered (ReorderableListView), and carry their own title and image — source: lib/widgets/section/list.dart
- Book metadata editor covers title, author (first/middle/last name, home page, nickname), genre, sequence (series), annotation, and cover page — source: lib/models/project.model.dart
- Saves the edited book as FictionBook 2 XML (`<?xml ...?><FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">...`) — source: lib/models/project.model.dart
- Exports a saved book to a user-chosen location through the system save-file dialog — source: lib/services/app.service.dart
- Local-first: workspace state (`fb2_workspace.json`) and book files are stored in the app documents directory; no server, API client, or account system appears anywhere in the source, and no HTTP client package is a dependency — source: lib/services/app.service.dart
- Keeps a "recent books" history of up to 10 opened projects — source: lib/services/app.service.dart
- Splits oversized sections (>500 paragraphs) into chunks when loading a book — source: lib/models/project.model.dart
- Bilingual user interface: English and Russian, switchable in settings — source: lib/utils/consts.dart
- Workspace settings include auto-save toggle, section-image visibility, image width, image quality, font size, and language — source: lib/widgets/forms/settings.form.dart
- Editing UI has two tabs per book: Info (metadata form) and Book (section list) — source: lib/pages/book_page.dart
- The repository contains tutorial GIFs and screenshots of the app's features (new section, delete section, cut/paste section, bold, emphasis, citations, save book) — source: resources/
- No active automated tests: the only test file is the default Flutter counter template, disabled (`.disabled`) — source: test/widget_test.dart.disabled

## Repository evidence

Concrete file paths in this repository that back the Verified facts.

- `pubspec.yaml` — name `quill_fb2`, description, Flutter SDK and dependencies (flutter_quill, file_picker, flutter_archive, xml, image_picker, path_provider, flutter_file_dialog, permission_handler), version 1.0.4+15, `publish_to: 'none'`, Android-only icon config
- `README.md` — one-line self-description
- `android/app/build.gradle` — applicationId, SDK versions, release signing config
- `lib/main.dart`, `lib/routes.dart` — app entry, Start/Home screens
- `lib/services/app.service.dart` — workspace persistence, load/save/export, zip handling, delta→FB2 XML conversion, history
- `lib/services/fb2.service.dart` — FB2 XML parsing and error-recovery parse loop
- `lib/models/project.model.dart` — ProjectModel: authors, genre, sequence, annotation, cover, binary resources, `getBookXml()`
- `lib/models/section.model.dart` — Section model, XML round-trip, delta conversion
- `lib/widgets/section_editor/editor.dart` — Quill-based section editor, save/export actions, per-section image panel
- `lib/widgets/section_editor/toolbar.dart` — custom Quill toolbar (links, color, headers, lists, indent, clear format, undo/redo)
- `lib/widgets/section/list.dart` — ReorderableListView section list with edit/delete actions
- `lib/widgets/forms/book_form.dart`, `lib/widgets/forms/settings.form.dart`, `lib/widgets/forms/image.dart`, `lib/widgets/forms/annotation.dart` — metadata and settings forms
- `lib/pages/home_page.dart`, `lib/pages/book_page.dart`, `lib/pages/start_page.dart`, `lib/pages/settings_page.dart` — screens; load book (.fb2/.zip), history list
- `lib/utils/consts.dart` — English/Russian translation tables, settings keys, history/section limits
- `lib/utils/cp1251.dart`, `lib/utils/common.dart` — Windows-1251 decoding, file helpers, image resize
- `resources/` — tutorial GIFs and screenshots
- `test/widget_test.dart.disabled` — the only (disabled, template) test file

## User-provided facts

Only the four non-derivable categories: production URL, primary goal, open-source status, features
not visible in the repository.

- Production URL: https://play.google.com/store/apps/details?id=com.caragulak.fb2editor (Google Play listing; package ID matches `android/app/build.gradle`) — source: user
- Primary goal: portfolio visibility — source: user
- Open-source status: public GitHub repository (`github.com/Basiliskin/FB2-Editor`), source-available license (viewing, personal builds and contributions allowed; redistribution and app-store publishing need written permission, and permitted redistributions must stay open-source under the same licence) — source: user. The `LICENSE` file is present at the repository root; `pubspec.yaml` still says `publish_to: 'none'` (package is not intended for pub.dev) — source: pubspec.yaml
- Features not visible in the repository: none provided; the user declined to add any — source: user

## Unknown

Gaps recorded as open. Never invent an answer here.

- Number of active users, installs, or ratings on Google Play
- Whether the Play Store listing is currently live and in which countries
- Performance benchmarks: maximum book size, parse/save speed, memory behavior
- Minimum supported Android version in practice (`minSdkVersion` defers to the Flutter default in `android/app/build.gradle`)
- iOS, desktop, or web support (the repo configures only an Android target; `flutter_icons` sets `ios: false`)
- Play Console statistics, review counts, or retention data
- Feature roadmap or planned work not present in the code
- Whether the FB2 files this editor produces pass third-party validators (no validation tooling in the repo)
- Exact authorship/licensing history predating the initial commit

## Forbidden assumptions

Never claim the following without explicit evidence. Un-evidenced occurrences are parked here, not in
Verified facts.

- fastest
- most secure
- better than competitors
- privacy-preserving

Note: "local-first / no server" is a code-verified fact (see Verified facts), but the editor must not
be marketed as "private", "secure", or "privacy-preserving" — files are stored in the app's private
documents directory by Flutter's default sandbox behavior, and no security audit or encryption
mechanism is evidenced in the repo.
