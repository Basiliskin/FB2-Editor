# FB2 Editor

A mobile and web editor for FictionBook (FB2) books. Users load a book as a project and edit it section by section.

## Language

**Section**:
A chapter-level unit of a book, with a title, paragraphs and an optional image.
_Avoid_: Chapter, page

**Paragraph range**:
A contiguous run of paragraphs within one Section.
_Avoid_: Block, chunk

## Story map

**Story map**:
A book's record of which Entities appear in which Section, and how they are tied together. People are found automatically from the text; everything else is added by hand or accepted from a Map proposal. It is saved inside the FB2 file.
_Avoid_: Plot, outline, character sheet

**Entity**:
One person, place, event or piece of lore on the Story map. It has a name, a kind, an optional note, and, for a person, a role (protagonist, major or minor).
_Avoid_: Character, item, object

**Presence**:
That an Entity appears in a Section. Counted from the text for people; a mark made by hand counts as one mention.
_Avoid_: Appearance, occurrence

**Tie**:
A link between two Entities, counted from paragraphs where both appear or drawn by hand, with an optional label such as "brother of".
_Avoid_: Relationship, edge, connection (in code)

**Act**:
One of up to three consecutive groups of Sections that the Story map cuts the book into by length. It is a way to read the timeline, not the book's plot structure.
_Avoid_: Part, volume

## AI assistance

**Provider**:
A user-defined connection to an LLM service: a vendor type (Gemini, OpenAI or Anthropic), an API key, a model name, an optional custom base URL and a Chunk limit. A user may save several; one is the default.
_Avoid_: Account, backend, integration

**Improvement**:
A request to a Provider to rewrite a selection or Paragraph range according to an instruction.
_Avoid_: Edit, enhancement, AI action

**Preset**:
A saved instruction for an Improvement, such as proofread, translate or restyle. A free-form instruction is an Improvement without a Preset.
_Avoid_: Template, macro

**Style note**:
A user-written, per-book instruction about tone and voice, sent with every Improvement for that book.
_Avoid_: Persona, system prompt

**Suggestion**:
The Provider's proposed replacement text, shown before and after the original. It changes the book only when the user accepts it.
_Avoid_: Result, output, patch

**Translate Preset**:
The Preset that translates text into a chosen language. It is an Improvement, so its Suggestions go through the Review queue. Entity names are kept spelled the same way (transliterated, never translated), and each Chunk sees the end of the previous translation.
_Avoid_: Translation mode, translator

**Chunk**:
A group of consecutive paragraphs from one Section sent to a Provider in a single request. A whole-Section Improvement is split into several Chunks.
_Avoid_: Batch, page

**Chunk limit**:
The most text a Provider is sent in one Chunk. Each Provider has its own, with a default for its vendor that the user can change.
_Avoid_: Context window, max tokens

**Review queue**:
The Suggestions from a whole-Section Improvement, one per Chunk, waiting for the user to accept or reject each. A Chunk that failed stays in the queue marked for retry. It is not kept if the app is closed.
_Avoid_: Inbox, backlog

**Analysis**:
A read-only request to a Provider about the book's text, such as a consistency check, a summary or a question. It never changes the book. Its result is Findings or an Answer.
_Avoid_: Query, scan, AI action

**Finding**:
One problem an Analysis reports, such as a name spelled two ways, with links to the Sections and paragraphs where it occurs. It can hand a fix to an Improvement, which then goes through the Review queue.
_Avoid_: Issue, error, warning

**Answer**:
The text an Analysis returns for a question or summary. It is shown, not applied.
_Avoid_: Response, output

**Name variant**:
One name written in more than one way in the book, such as Ivan and Иван, or Фёдор and Федор. It is the kind of Finding the names check reports. Whether two spellings are the same person is the user's call; the app only proposes it.
_Avoid_: Typo, alias, duplicate

**Map proposal**:
One thing an Analysis of the Story map suggests: a place, event or piece of lore to add (with its mentions counted from the text), or a label for a Tie. It is dropped unless the book's text bears it out, and it reaches the map only when the user accepts it.
_Avoid_: Suggestion (that is a rewrite of text), Finding

**Digest**:
A short summary of one Section, or of a part of a Section too long for one request, made by a Provider and kept on the device so the same text is never summarised twice. A long Analysis works from Digests instead of the full text.
_Avoid_: Abstract, synopsis, cache entry
