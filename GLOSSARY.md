# FB2 Editor

A mobile and web editor for FictionBook (FB2) books. Users load a book as a project and edit it section by section.

## Language

**Section**:
A chapter-level unit of a book, with a title, paragraphs and an optional image.
_Avoid_: Chapter, page

**Paragraph range**:
A contiguous run of paragraphs within one Section.
_Avoid_: Block, chunk

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
