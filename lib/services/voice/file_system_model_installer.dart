import 'dart:async';
import 'dart:io';

import 'install_failure.dart';
import 'model_installer.dart';
import 'speech_model_files.dart';
import 'https_file_fetcher.dart';
import 'sha256_file.dart';

/// A file the installer puts in place, and the exact bytes it must have.
typedef PinnedModelFile = ({
  String name,
  int sizeInBytes,
  String sha256,
  Uri url,
});

/// Installs the Speech Model into one directory on the phone.
///
/// Downloads land as `<name>.part` in a sibling staging directory, which is
/// on the same volume, so verified files reach the model directory by rename
/// and the model directory never holds a partial or unverified file.
class FileSystemModelInstaller implements ModelInstaller {
  FileSystemModelInstaller({
    required Directory modelDirectory,
    HttpsFileFetcher? fetcher,
    List<PinnedModelFile>? files,
  }) : _modelDirectory = modelDirectory,
       _staging = Directory('${modelDirectory.path}.staging'),
       _fetcher = fetcher ?? HttpsFileFetcher(),
       _files = files ?? _speechModelFiles;

  static final _speechModelFiles = [
    for (final file in SpeechModelFile.all)
      (
        name: file.name,
        sizeInBytes: file.sizeInBytes,
        sha256: file.sha256,
        url: Uri.parse(file.downloadUrl),
      ),
  ];

  final Directory _modelDirectory;
  final Directory _staging;
  final HttpsFileFetcher _fetcher;
  final List<PinnedModelFile> _files;

  /// Checks sizes only: a file reaches the model directory after its SHA-256
  /// matched, so hashing again would delay every app start by seconds.
  @override
  Future<bool> isInstalled() async {
    for (final file in _files) {
      final installed = File(_installedPath(file));
      if (!await installed.exists() ||
          await installed.length() != file.sizeInBytes) {
        return false;
      }
    }
    return true;
  }

  @override
  Stream<int> download() async* {
    if (await isInstalled()) return;
    try {
      await _staging.create(recursive: true);
      var received = 0;
      for (final file in _files) {
        await for (final staged in _stage(file)) {
          yield received + staged;
        }
        received += file.sizeInBytes;
        yield received;
      }
      await _moveIntoModelDirectory();
    } on FileSystemException {
      throw const StorageFailure();
    }
  }

  /// Emits the bytes of [file] on disk so far. Leaves a verified, full-size
  /// `.part` behind, or keeps a partial one for the next attempt to resume.
  Stream<int> _stage(PinnedModelFile file) async* {
    final part = File(_partPath(file));
    var length = await part.exists() ? await part.length() : 0;
    if (length > file.sizeInBytes) {
      await part.delete();
      length = 0;
    }

    if (length < file.sizeInBytes) {
      final body = await _fetcher.fetch(file.url, from: length);
      final sink = await part.open(
        mode: body.offset == 0 ? FileMode.write : FileMode.append,
      );
      length = body.offset;
      try {
        await for (final chunk in body.bytes) {
          length += chunk.length;
          if (length > file.sizeInBytes) break;
          await sink.writeFrom(chunk);
          yield length;
        }
      } finally {
        await sink.close();
      }
      if (length < file.sizeInBytes) throw const NetworkFailure();
    }

    if (!await _partIsIntact(file)) {
      await part.delete();
      throw const FingerprintMismatch();
    }
  }

  Future<bool> _partIsIntact(PinnedModelFile file) async {
    final part = File(_partPath(file));
    return await part.exists() &&
        await part.length() == file.sizeInBytes &&
        await sha256OfFile(part.path) == file.sha256;
  }

  Future<void> _moveIntoModelDirectory() async {
    await _modelDirectory.create(recursive: true);
    for (final file in _files) {
      await File(_partPath(file)).rename(_installedPath(file));
    }
    await _staging.delete(recursive: true);
  }

  String _installedPath(PinnedModelFile file) =>
      '${_modelDirectory.path}/${file.name}';

  String _partPath(PinnedModelFile file) =>
      '${_staging.path}/${file.name}.part';
}
