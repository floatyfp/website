import 'dart:async';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';
import 'package:website/database.dart';
import 'session_sql.dart';

/// Manages editor sessions with TTL.
class SessionManager {
  static final _uuid = Uuid();
  static const _ttl = Duration(hours: 1);

  /// Default TTL for sessions (seconds).
  static int get ttlSeconds => _ttl.inSeconds;

  /// Creates a new session with metadata: mode ('new'|'edit'), optional postId, type, and metadata.
  static String createSession({
    required String mode,
    String? postId,
    String? postType,
    Map<String, dynamic>? metadata,
  }) {
    final id = _uuid.v4();
    final expiresAt = DateTime.now().add(_ttl);
    // Store in SQLite with metadata as JSON string
    SessionSql.insertSession(
      id, 
      mode, 
      postId, 
      postType, 
      expiresAt,
      metadata: metadata != null ? jsonEncode(metadata) : null,
    );
    return id;
  }

  /// Validates and consumes a session. Returns true if valid.
  static bool validate(String id) {
    final row = SessionSql.getSession(id);
    if (row == null) return false;
    final expiresAt = DateTime.parse(row['expiresAt'] as String);
    if (DateTime.now().isAfter(expiresAt)) {
      SessionSql.deleteSession(id);
      return false;
    }
    SessionSql.deleteSession(id); // consume
    return true;
  }

  /// Retrieves metadata for a session without consuming.
  static SessionData? getData(String id) {
    final row = SessionSql.getSession(id);
    if (row == null) return null;
    return SessionData(
      mode: row['mode'] as String,
      postId: row['postId'] as String?,
      postType: row['postType'] as String?,
      metadataJson: row['metadata'] as String?,
    );
  }

  /// Periodic cleanup of expired sessions.
  static void startCleanup() {
    Timer.periodic(Duration(minutes: 1), (_) {
      SessionSql.clearExpired();
    });
  }
}

/// Metadata for an editor session.
class SessionData {
  final String mode;
  final String? postId;
  final String? postType;
  final String? metadataJson;
  
  Map<String, dynamic>? get metadata => 
      metadataJson != null ? jsonDecode(metadataJson!) : null;
      
  SessionData({required this.mode, this.postId, this.postType, this.metadataJson});
  
  SessionData.withMap({
    required String mode, 
    String? postId, 
    String? postType, 
    Map<String, dynamic>? metadata
  }) : this(
    mode: mode,
    postId: postId,
    postType: postType,
    metadataJson: metadata != null ? jsonEncode(metadata) : null,
  );
}

// GET /api/session-metadata?sessionId=...
Future<Response> sessionMetadataHandler(Request req) async {
  try {
    final sessionId = req.url.queryParameters['sessionId'];
    if (sessionId == null) {
      return Response(400,
          body: jsonEncode({'error': 'Missing sessionId'}),
          headers: {'content-type': 'application/json'});
    }
    final session = SessionManager.getData(sessionId.toString());
    if (session == null) {
      return Response(403,
          body: jsonEncode({'error': 'Invalid session'}),
          headers: {'content-type': 'application/json'});
    }
    Map<String, dynamic> data = {
      'mode': session.mode,
      'postType': session.postType,
    };
    if (session.mode == 'edit' && session.postId != null) {
      if (!DatabaseManager.isDBInitialized()) {
        DatabaseManager.init();
      }
      data['postId'] = session.postId;
      final rows = DatabaseManager.db
          .select('SELECT * FROM posts WHERE id = ?', [session.postId]);
      Map<String, dynamic>? row;

      if (rows.isNotEmpty) {
        row = rows.first;
      } else {
        // If not found in posts, check scheduled_posts
        final scheduledRows = DatabaseManager.db.select(
            'SELECT * FROM scheduled_posts WHERE id = ?', [session.postId]);
        if (scheduledRows.isNotEmpty) {
          row = scheduledRows.first;
        }
      }

      if (row != null) {
        data['post'] = {
          'title': row['title'],
          'content': row['content'],
          'summary': row['summary'],
          'url': row['url'],
          'tags': () {
            final tagsRaw = row!['tags'];
            if (tagsRaw == null) return <String>[];
            try {
              final decoded = jsonDecode(tagsRaw as String);
              if (decoded is List) {
                return decoded.map((e) => e.toString()).toList();
              }
            } catch (_) {}
            return <String>[];
          }(),
          'thumbnail': row['thumbnail'],
          'dropdowns': () {
            final dropdownsRaw = row!['dropdowns'];
            if (dropdownsRaw == null) return <dynamic>[];
            try {
              final decoded = jsonDecode(dropdownsRaw as String);
              if (decoded is List) {
                return decoded;
              }
            } catch (_) {}
            return <dynamic>[];
          }(),
          'author': row['author'],
          'version': row['version'],
        };
      }
    }
    return Response.ok(jsonEncode(data),
        headers: {'content-type': 'application/json'});
  } catch (e) {
    print(e);
    return Response.internalServerError(
        body: jsonEncode({'error': 'Could not fetch session metadata'}),
        headers: {'content-type': 'application/json'});
  }
}
