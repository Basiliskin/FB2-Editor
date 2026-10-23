/// Why a picked file could not be opened as a book.
enum OpenFailureKind {
  /// Not an .fb2 or .zip file.
  unsupportedType,

  /// The file could not be read or copied.
  unreadable,

  /// A .zip archive with no .fb2 inside.
  noFb2InZip,

  /// Readable, but not a FictionBook document.
  notFb2,

  /// Readable, but not an EPUB book.
  notEpub,

  /// Parsing did not finish in time.
  timeout,
}

class OpenFailure implements Exception {
  final OpenFailureKind kind;
  final String? detail;
  const OpenFailure(this.kind, [this.detail]);

  @override
  String toString() => 'OpenFailure(${kind.name}${detail == null ? '' : ': $detail'})';
}
