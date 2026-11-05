import 'dart:convert';
import '../network/token_storage.dart';

/// Persists in-progress voter ballot decisions locally so that an unexpected
/// session expiration, network drop, or browser restart never causes voters
/// to lose their candidate selections.
class BallotDraftStorage {
  static String _key(String electionId) => 'ballot_draft_$electionId';

  /// Save ballot choices to local device storage
  static Future<void> saveDraft(String electionId, Map<String, List<String>> selections) async {
    try {
      if (selections.isEmpty || !selections.values.any((list) => list.isNotEmpty)) {
        await clearDraft(electionId);
        return;
      }
      final jsonStr = jsonEncode(selections);
      await TokenStorage.write(_key(electionId), jsonStr);
    } catch (_) {
      // Local caching is best-effort and non-fatal
    }
  }

  /// Load existing ballot draft from local device storage
  static Future<Map<String, List<String>>?> loadDraft(String electionId) async {
    try {
      final raw = await TokenStorage.read(_key(electionId));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final result = <String, List<String>>{};
        for (final entry in decoded.entries) {
          if (entry.value is List) {
            result[entry.key.toString()] = (entry.value as List).map((e) => e.toString()).toList();
          }
        }
        return result.isNotEmpty ? result : null;
      }
    } catch (_) {
      // Ignore corrupted cache
    }
    return null;
  }

  /// Clear the draft when the vote is successfully cast and confirmed by the server
  static Future<void> clearDraft(String electionId) async {
    try {
      await TokenStorage.delete(_key(electionId));
    } catch (_) {
      // Best-effort
    }
  }
}
