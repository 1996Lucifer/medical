import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

class SecureStorageService {
  static final SecureStorageService _instance = SecureStorageService._internal();
  static SecureStorageService get instance => _instance;

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  SecureStorageService._internal();

  /// Save a patient SOAP note securely on the device
  Future<void> savePatientNote(String patientName, Map<String, dynamic> noteData) async {
    final String jsonString = jsonEncode(noteData);
    final String key = 'note_${patientName}_${DateTime.now().millisecondsSinceEpoch}';
    
    // We store an index of keys so we can retrieve them later
    await _addKeyToIndex(key);
    
    await _storage.write(key: key, value: jsonString);
  }

  /// Retrieve all securely saved patient notes
  Future<List<Map<String, dynamic>>> getAllPatientNotes() async {
    final String? indexString = await _storage.read(key: 'note_keys_index');
    if (indexString == null) return [];

    final List<dynamic> keys = jsonDecode(indexString);
    final List<Map<String, dynamic>> notes = [];

    for (var key in keys) {
      final String? noteString = await _storage.read(key: key);
      if (noteString != null) {
        notes.add(jsonDecode(noteString));
      }
    }
    
    return notes;
  }

  Future<void> _addKeyToIndex(String key) async {
    final String? indexString = await _storage.read(key: 'note_keys_index');
    List<String> keys = [];
    
    if (indexString != null) {
      final List<dynamic> decoded = jsonDecode(indexString);
      keys = decoded.cast<String>();
    }
    
    keys.add(key);
    await _storage.write(key: 'note_keys_index', value: jsonEncode(keys));
  }

  /// Delete a specific note
  Future<void> deleteNote(String key) async {
    await _storage.delete(key: key);
    
    // Remove from index
    final String? indexString = await _storage.read(key: 'note_keys_index');
    if (indexString != null) {
      List<String> keys = jsonDecode(indexString).cast<String>();
      keys.remove(key);
      await _storage.write(key: 'note_keys_index', value: jsonEncode(keys));
    }
  }
}
