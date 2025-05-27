import 'dart:async';
import 'dart:convert';
import 'package:dotenv/dotenv.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'session_manager.dart';
import 'database.dart';

// Registry of connected WS clients (metadata)
final List<Map<String, dynamic>> connectedClients = [];
// Exported list of connected WebSocketChannel clients for broadcasting
final Map<String, WebSocketChannel> globalWebSocketClients = {};
// Ping interval in seconds
const int _pingInterval = 30;
// Client timeout in seconds (2 missed pings)
const int _clientTimeout = _pingInterval * 3; // 90 seconds

/// Creates a WebSocket handler with token auth and session logic.
Handler wsHandler() {
  final env = DotEnv(includePlatformEnvironment: true)..load();
  // Clean up dead connections periodically
  Timer.periodic(Duration(seconds: _pingInterval * 2), (timer) {
    final now = DateTime.now();
    final deadClients = <String>[];
    
    globalWebSocketClients.forEach((id, socket) {
      try {
        final client = connectedClients.firstWhere(
          (c) => c['id'] == id,
          orElse: () => {'lastSeen': now.toIso8601String()},
        );
        
        final lastSeen = DateTime.parse(client['lastSeen']);
        if (now.difference(lastSeen).inSeconds > _clientTimeout) {
          print('Closing dead connection: $id');
          deadClients.add(id);
          try {
            socket.sink.close(ws_status.goingAway);
          } catch (e) {
            print('Error closing dead connection $id: $e');
          }
        }
      } catch (e) {
        print('Error checking client $id: $e');
        deadClients.add(id);
      }
    });
    
    // Clean up
    for (final id in deadClients) {
      try {
        globalWebSocketClients.remove(id);
        connectedClients.removeWhere((client) => client['id'] == id);
      } catch (e) {
        print('Error cleaning up client $id: $e');
      }
    }
  });

  final socketHandler = webSocketHandler((WebSocketChannel socket, String? protocol) {
    final clientId = DateTime.now().millisecondsSinceEpoch.toString();
    print('WebSocket connection established (ID: $clientId, protocol: $protocol)');
    
    // Start TTL cleanup
    SessionManager.startCleanup();
    
    // Track client connection
    globalWebSocketClients[clientId] = socket;
    Timer? pingTimer;
    DateTime? lastPingTime;
    bool isAlive = true;
    
    // Function to send pings
    void startPingTimer() {
      pingTimer?.cancel();
      pingTimer = Timer.periodic(Duration(seconds: _pingInterval), (timer) {
        if (!isAlive) {
          print('Closing dead connection: $clientId');
          socket.sink.close(ws_status.goingAway);
          timer.cancel();
          return;
        }
        
        isAlive = false;
        lastPingTime = DateTime.now();
        try {
          socket.sink.add(jsonEncode({
            'type': 'ping',
            'timestamp': lastPingTime!.millisecondsSinceEpoch,
          }));
        } catch (e) {
          print('Error sending ping to $clientId: $e');
          timer.cancel();
          socket.sink.close(ws_status.goingAway);
        }
      });
    }
    
    // Handle connection close
    socket.sink.done.then((_) {
      print('WebSocket connection closed: $clientId');
      pingTimer?.cancel();
      globalWebSocketClients.remove(clientId);
      connectedClients.removeWhere((client) => client['id'] == clientId);
    }).catchError((error) {
      print('WebSocket error for $clientId: $error');
      pingTimer?.cancel();
      globalWebSocketClients.remove(clientId);
      connectedClients.removeWhere((client) => client['id'] == clientId);
    });
    
    // Start the ping timer
    startPingTimer();
    
    // Handle incoming messages
    socket.stream.listen((dynamic data) {
      if (data is! String) return;
      
      Map<String, dynamic> msg;
      try {
        msg = jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {
        return;
      }
      
      // Handle ping-pong messages
      if (msg['type'] == 'pong') {
        final timestamp = msg['timestamp'] as int?;
        if (timestamp != null && lastPingTime != null) {
          final latency = DateTime.now().millisecondsSinceEpoch - timestamp;
          print('Ping latency for $clientId: ${latency}ms');
        }
        isAlive = true;
        return;
      }
      
      final rid = msg['requestId'] as String?;
      final type = msg['type'] as String?;
      if (type == 'identify') {
        // Update or add client info
        final clientInfo = {
          'id': clientId,
          'name': msg['name'] as String? ?? 'unknown',
          'connectedTime': DateTime.now().toIso8601String(),
          'lastSeen': DateTime.now().toIso8601String(),
        };

        // Remove if already exists (reconnection)
        connectedClients.removeWhere((client) => client['id'] == clientId);
        connectedClients.add(clientInfo);
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
      } else if (type == 'get_last_deployment_id') {
        final db = DatabaseManager.db;
        final rows = db.select(
            'SELECT id FROM deployments ORDER BY created_at DESC LIMIT 1');
        if (rows.isEmpty) {
          socket.sink.add(jsonEncode({
            'type': 'last_deployment_id_result',
            'error': 'No deployments found',
            if (rid != null) 'requestId': rid
          }));
        } else {
          socket.sink.add(jsonEncode({
            'type': 'last_deployment_id_result',
            'deploymentId': rows.first['id'].toString(),
            if (rid != null) 'requestId': rid
          }));
        }
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
