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
A book's record of which Entities appear in which Section, and how they are tied together. People are found automatically from the text; everything else is added by hand. It is saved inside the FB2 file.
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
A user-defined connection to an LLM service: a vendor type (Gemini, OpenAI or Anthropic), an API key, a model name and an optional custom base URL. A user may save several; one is the default.
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
