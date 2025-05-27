import 'dart:async';

import 'package:dotenv/dotenv.dart';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'session_manager.dart';
import 'database.dart';

// Registry of connected WS clients (metadata)
final List<Map<String, String>> connectedClients = [];
// Exported list of connected WebSocketChannel clients for broadcasting
final List<WebSocketChannel> globalWebSocketClients = [];

/// Creates a WebSocket handler with token auth and session logic.
Handler wsHandler() {
  final env = DotEnv(includePlatformEnvironment: true)..load();
  final socketHandler =
      webSocketHandler((WebSocketChannel socket, String? protocol) {
    print('WebSocket connection established (protocol: $protocol)');
    // start TTL cleanup
    SessionManager.startCleanup();
    Pinger.start(socket);
    globalWebSocketClients.add(socket);
    socket.stream.listen((dynamic data) {
      if (data is! String) return;
      Map<String, dynamic> msg;
      try {
        msg = jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {
        return;
      }
      final rid = msg['requestId'] as String?;
      final type = msg['type'] as String?;
      if (type == 'identify') {
        connectedClients.add({
          'name': msg['name'] as String? ?? 'unknown',
          'connectedTime': DateTime.now().toIso8601String()
        });
        socket.sink.add(jsonEncode(
            {'type': 'identify_ack', if (rid != null) 'requestId': rid}));
      } else if (type == 'create_session') {
        String? postType = msg['postType'];
        final mode = msg['mode'] as String?;
        final postId = msg['postId'] as String?;
        // If editing and postType is not provided, fetch from DB
        if (mode == 'edit' && (postType == null || postType.isEmpty)) {
          final db = DatabaseManager.db;
          // Try by postId first
          if (postId != null && postId.isNotEmpty) {
            final rows =
                db.select('SELECT type FROM posts WHERE id = ?', [postId]);
            if (rows.isNotEmpty) {
              postType = rows.first['type'] as String?;
            }
          }
          // Optionally, try by slug if postId is not available (future-proof)
          if ((postType == null || postType.isEmpty) && msg['slug'] != null) {
            final slug = msg['slug'] as String;
            final rows =
                db.select('SELECT type FROM posts WHERE url = ?', [slug]);
            if (rows.isNotEmpty) {
              postType = rows.first['type'] as String?;
            }
          }
        }
        print(postType);
        final id = SessionManager.createSession(
            mode: mode ?? '',
            postId: postId,
            postType: postType,
            metadata: msg['metadata'] as Map<String, dynamic>?);
        socket.sink.add(jsonEncode({
          'type': 'session_created',
          'sessionId': id,
          'expiresIn': SessionManager.ttlSeconds,
          if (rid != null) 'requestId': rid
        }));
      } else if (type == 'slug_to_id') {
        final slug = msg['slug'] as String?;
        if (slug == null || slug.isEmpty) {
          socket.sink.add(jsonEncode({
            'type': 'slug_to_id_result',
            'error': 'Missing slug',
            if (rid != null) 'requestId': rid
          }));
        } else {
          // Query DB for post ID by slug
          final db = DatabaseManager.db;
          final rows = db.select('SELECT id FROM posts WHERE url = ?', [slug]);
          if (rows.isEmpty) {
            socket.sink.add(jsonEncode({
              'type': 'slug_to_id_result',
              'error': 'Not found',
              if (rid != null) 'requestId': rid
            }));
          } else {
            socket.sink.add(jsonEncode({
              'type': 'slug_to_id_result',
              'id': rows.first['id'],
              'title': rows.first['title'],
              if (rid != null) 'requestId': rid
            }));
          }
        }
      } else if (type == 'delete_post') {
        final postId = msg['postId'] as String?;
        if (postId == null || postId.isEmpty) {
          socket.sink.add(jsonEncode({
            'type': 'delete_post_result',
            'error': 'Missing postId',
            if (rid != null) 'requestId': rid
          }));
        } else {
          final db = DatabaseManager.db;
          final stmt = db.prepare('DELETE FROM posts WHERE id = ?');
          stmt.execute([postId]);
          stmt.dispose();
          if (db.select('SELECT 1 FROM posts WHERE id = ?', [postId]).isEmpty) {
            socket.sink.add(jsonEncode({
              'type': 'delete_post_result',
              'status': 'ok',
              'postId': postId,
              if (rid != null) 'requestId': rid
            }));
          } else {
            socket.sink.add(jsonEncode({
              'type': 'delete_post_result',
              'error': 'Delete failed',
              'postId': postId,
              if (rid != null) 'requestId': rid
            }));
          }
        }
      } else if (type == 'list_clients') {
        socket.sink.add(jsonEncode({
          'type': 'clients',
          'clients': connectedClients,
          if (rid != null) 'requestId': rid
        }));
      } else if (type == 'set_required') {
        final deploymentId = msg['deploymentId'];
        if (deploymentId == null || deploymentId.toString().isEmpty) {
          socket.sink.add(jsonEncode({
            'type': 'set_required_result',
            'status': 'error',
            'error': 'Missing deploymentId',
            if (rid != null) 'requestId': rid
          }));
        } else {
          final db = DatabaseManager.db;
          final stmt =
              db.prepare('UPDATE deployments SET required = 1 WHERE id = ?');
          stmt.execute([deploymentId]);
          stmt.dispose();
          socket.sink.add(jsonEncode({
            'type': 'set_required_result',
            'status': 'ok',
            'deploymentId': deploymentId,
            if (rid != null) 'requestId': rid
          }));
        }
      } else {
        socket.sink.add(
            jsonEncode({'type': 'error', 'message': 'Unknown message type'}));
      }
    }, onDone: () {
      globalWebSocketClients.remove(socket);
    }, onError: (_) {
      globalWebSocketClients.remove(socket);
    });
  });
  final handler = socketHandler;
  return (Request request) {
    final expected = env['WS_PASSWORD'] ?? 'changeme';
    final token = request.url.queryParameters['token'];
    if (token != expected) return Response.forbidden('Invalid token');
    return handler(request);
  };
}

class Pinger {
  static void start(WebSocketChannel socket) {
    Timer.periodic(const Duration(seconds: 85), (timer) {
      socket.sink.add(jsonEncode({'type': 'ping'}));
    });
  }
}
