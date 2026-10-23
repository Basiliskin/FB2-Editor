import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Holds API keys apart from the workspace file, so exports never carry them.
abstract class KeyVault {
  Future<String?> read(String providerId);
  Future<void> write(String providerId, String key);
  Future<void> delete(String providerId);
}

/// Lives only as long as the app session; the default on web.
class MemoryKeyVault implements KeyVault {
  final Map<String, String> _keys = {};
  @override
  Future<String?> read(String id) async => _keys[id];
  @override
  Future<void> write(String id, String key) async => _keys[id] = key;
  @override
  Future<void> delete(String id) async => _keys.remove(id);
}

/// Android Keystore, or browser storage on web (opt-in only).
class SecureKeyVault implements KeyVault {
  final FlutterSecureStorage _storage;
  SecureKeyVault([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();
  String _k(String id) => 'llm-key-$id';
  @override
  Future<String?> read(String id) => _storage.read(key: _k(id));
  @override
  Future<void> write(String id, String key) =>
      _storage.write(key: _k(id), value: key);
  @override
  Future<void> delete(String id) => _storage.delete(key: _k(id));
}
