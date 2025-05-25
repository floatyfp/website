import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'database.dart';

/// Returns a matrix of { platform: { channel: boolean } } for latest visible deployment per channel
Future<Response> platformChannelMatrixHandler(Request req) async {
  // Define supported platforms and channels
  const platforms = ['windows', 'macos', 'linux', 'android', 'ios'];
  const channels = ['release', 'beta', 'nightly'];

  // For each platform and channel, find the latest visible deployment
  final matrix = <String, Map<String, bool>>{};
  for (final platform in platforms) {
    matrix[platform] = {};
    for (final channel in channels) {
      final sql = '''
        SELECT info_json FROM deployments
        WHERE visible = 1
          AND flavor = ?
        ORDER BY created_at DESC
        LIMIT 10
      ''';
      final rows = DatabaseManager.db.select(sql, [channel]);
      bool found = false;
      for (final row in rows) {
        final info = jsonDecode(row['info_json'] as String);
        if (info['platforms'] is List &&
            (info['platforms'] as List).any((p) => p['platform'] == platform)) {
          found = true;
          break;
        }
      }
      matrix[platform]![channel] = found;
    }
  }
  return Response.ok(jsonEncode({'matrix': matrix}),
      headers: {'content-type': 'application/json'});
}
