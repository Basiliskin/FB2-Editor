# Play Data safety and privacy policy for "Improve with AI"

Answers come from the code. Items marked **CONFIRM** are things only the developer can know.

## What changed in the app

- New `INTERNET` permission in the release manifest. Before this the app made no network calls.
- Optional feature: the user adds their own AI provider (Gemini, OpenAI or Anthropic, or a custom
  https base URL) with their own API key, then asks it to improve selected paragraphs.
- The app has no backend of its own. Requests go from the device straight to the provider the user
  chose. The developer receives nothing.

## Data flow (verified in code)

| Data | Where it goes | When | Source |
|---|---|---|---|
| Text of the selected paragraphs, with inline FB2 tags | The user's chosen provider | Only after the user taps Improve and confirms the "send" dialog | `lib/services/llm/improvement.dart` |
| Book metadata (title, author) and the per-book Style note | Same provider, in the same request | Same | `ImprovementContext` |
| The user's instruction or Preset | Same provider | Same | `improvement.dart` |
| Paragraphs chosen for Translate, the end of the previous translation, names from the story map and the section title | The user's chosen provider | Only after the user picks a language and, above 3 requests (or on first use), confirms the dialog that shows the size | `lib/widgets/section_editor/improve_controller.dart` |
| Short quotes (about a sentence each) around names the local names check could not decide, at most 40 pairs per run | The user's chosen provider | Only after the user taps Ask AI in Check names and confirms the dialog that shows the size | `lib/services/name_check_ai.dart`, `lib/pages/names_check_page.dart` |
| Text of the Sections the user chose in Ask about the book, and the user's question; for long ranges, each Section is sent once to be summarised | The user's chosen provider | Only after the user taps Summarise or Ask and confirms the dialog that shows the size and number of requests | `lib/services/book_ask.dart`, `lib/pages/ask_page.dart` |
| Short summaries (Digests) of Sections made by the provider | Stored on the device in the workspace JSON, capped at 500; never sent anywhere else | n/a | `DigestStore` |
| API key | Sent to the chosen provider as authentication. Stored on the device in Android Keystore-backed secure storage, never in the book, the workspace JSON or exports | On use | `key_vault.dart` |
| Connection test | A tiny test request to the provider | Only when the user taps Test connection | `adapters.dart` |

Nothing is sent automatically. A consent dialog appears the first time a provider is used. The app
has no analytics, crash reporting or advertising SDK (see `pubspec.yaml`).

## Data safety form answers

Console wording defines "Collected" as data transmitted off the device "to you or a third party", so
sending book text to the user's chosen AI provider counts as collected as well as shared. The
user-initiated-transfer exemption is not relied on; over-declaring only lengthens the store label.

| Data type | Collected | Shared | Ephemeral | Optional | Purpose |
|---|---|---|---|---|---|
| App activity: Other user-generated content (book text) | Yes | Yes | No | Yes, only if the user uses Improve, Translate, Ask AI in Check names or Ask about the book | App functionality (both) |

Deliberately not declared:
- **Name**: the author in book metadata is book content, not the app user's name.
- **Other info (API key)**: the user's own credential for their own vendor account, sent only to
  that vendor as authentication. The app has no accounts of its own.
- Everything else (location, contacts, IDs, diagnostics, ...): no such code.

Other answers:
- Collects or shares data: Yes.
- Encrypted in transit: Yes (release builds are https-only).
- Account creation: "My app does not allow users to create an account"; no login with outside accounts.
- Data deletion request: left unanswered (optional); the developer holds no data.

Preview in Console (reached, **not saved**) shows "Data shared" and "Data collected" both as
App activity > Other user-generated content, and "Data is encrypted in transit".

## Status

1. **Data safety form:** filled in and saved in Play Console (staged in Publishing overview, to go to
   review with the release).
2. **AD_ID permission:** removed from the manifest (`78144f2`). When the build goes up, set the
   *Advertising ID* declaration (App content) to **No**; it currently says Yes.
3. **Privacy policy.** Console links a hosted policy at freeprivacypolicy.com (the Preview step shows the
   full URL). The wording below has to be added there; it is not in this repo.
4. **Release notes** for the version should mention the new optional AI feature and that it needs
   the user's own API key.

## Privacy policy wording (draft)

> **AI-assisted improvement (optional).** FB2 Editor can send text from your book to an AI service
> so that it can suggest improvements. This feature is off until you add your own AI provider
> (Google Gemini, OpenAI or Anthropic, or a compatible service at an address you enter) and your own
> API key in Settings.
>
> When you ask for an improvement, the app sends the paragraphs you selected, the book's title and
> author, your style note and your instruction directly from your device to the provider you chose.
> Nothing is sent without your action, and the app asks for your confirmation the first time you use
> a provider. We do not operate a server for this feature and we do not receive, store or see your
> text or your key.
>
> The same applies to "Check names" in the story map. The check itself runs on your device. Only if
> you tap "Ask AI" does the app send short quotes around names it could not decide about (a few
> sentences per name, for at most 40 pairs) to your chosen provider, after you confirm what will be
> sent. Nothing else from the book is sent.
>
> "Ask about the book" works the same way. When you summarise a range of sections or ask a question,
> the app sends the text of the sections you chose to your provider, and your question, after you
> confirm the size. For a long range it first sends each section to get a short summary and keeps
> those summaries on your device so the same text is not sent twice. Nothing in your book is changed.
>
> "Translate" works the same way. The app sends the paragraphs you chose, in several requests if needed, together with the end of the previous translation, the names from your story map and the section title, to your provider, after you confirm. Nothing is sent unless you ask.
>
> What the provider does with the text is governed by that provider's own terms and privacy policy,
> which you accept when you create your account and key with them.
>
> Your API key is stored only on your device, in the Android secure storage. It is not saved in your
> book files, exports or backups made by the app.
>
> The app contains no advertising, analytics or crash-reporting services. *(CONFIRM: remove this
> sentence if the existing policy says otherwise or the AD_ID question above changes.)*
