import 'database.dart';

/// Helper functions for session storage in SQLite.
class SessionSql {
  static void insertSession(
    String id, 
    String mode, 
    String? postId,
    String? postType, 
    DateTime expiresAt, {
    String? metadata,
  }) {
    final stmt = DatabaseManager.db.prepare('''
      INSERT OR REPLACE INTO sessions(id, mode, postId, postType, expiresAt, metadata)
      VALUES (?, ?, ?, ?, ?, ?)
    ''');
    stmt.execute([
      id,
      mode,
      postId,
      postType,
      expiresAt.toIso8601String(),
      metadata,
    ]);
    stmt.dispose();
  }

  static Map<String, dynamic>? getSession(String id) {
    final rows =
        DatabaseManager.db.select('SELECT * FROM sessions WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    final original = rows.first;
    final row = Map<String, dynamic>.from(original);
    // Keep metadata as JSON string - parsing will be handled by SessionData
    return row;
  }

  static void deleteSession(String id) {
    final stmt =
        DatabaseManager.db.prepare('DELETE FROM sessions WHERE id = ?');
    stmt.execute([id]);
    stmt.dispose();
  }

  static void clearExpired() {
    final now = DateTime.now().toIso8601String();
    final stmt =
        DatabaseManager.db.prepare('DELETE FROM sessions WHERE expiresAt < ?');
    stmt.execute([now]);
    stmt.dispose();
  }
}
