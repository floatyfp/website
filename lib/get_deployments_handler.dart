import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'database.dart';

/// Handles GET /api/deployments?platform=windows&channel=release=1&limit=1
Future<Response> getDeploymentsHandler(Request req) async {
  try {
    final platform = req.url.queryParameters['platform'];
    final channel = req.url.queryParameters['channel'];
    final version = req.url.queryParameters['version'];
    final limit = int.tryParse(req.url.queryParameters['limit'] ?? '10') ?? 10;

    // Query deployments table for visible deployments, optionally filtered by platform/channel/version
    var sql = 'SELECT * FROM deployments WHERE 1=1 AND visible = 1';
    final params = <dynamic>[];
    if (channel != null && channel.isNotEmpty) {
      sql += ' AND flavor = ?';
      params.add(channel);
    }
    if (version != null && version.isNotEmpty) {
      sql += " AND json_extract(info_json, '\$.version') = ?";
      params.add(version);
    }
    sql += ' ORDER BY created_at DESC LIMIT ?';
    params.add(limit);
    final rows = DatabaseManager.db.select(sql, params);
    final deployments = rows.map((row) {
      final info = jsonDecode(row['info_json'] as String);
      // Extract files for the requested platform, or all if not specified
      List<dynamic> files = [];
      if (info['platforms'] is List) {
        if (platform != null && platform.isNotEmpty) {
          final plat = (info['platforms'] as List).firstWhere(
            (p) => p['platform'] == platform,
            orElse: () => null,
          );
          if (plat != null && plat['files'] is List) {
            files = List.from(plat['files']);
          }
        } else {
          // Aggregate all files for all platforms
          for (final plat in info['platforms']) {
            if (plat['files'] is List) {
              files.addAll(plat['files']);
            }
          }
        }
      }
      return {
        'version': info['version'],
        'flavor': info['flavor'],
        'platform': platform,
        'date': row['created_at'],
        'files': files,
        'changelog': '/changelogs#${row['id']}'
      };
    }).toList();
    return Response.ok(jsonEncode({'deployments': deployments}),
        headers: {'content-type': 'application/json'});
  } catch (e) {
    return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'});
  }
}

/// Handles GET /api/latest-update
Future<Response> latestUpdateHandler(Request req) async {
  try {
    // Optionally filter by flavor, default to latest 'release' deployment
    final flavor = req.url.queryParameters['flavor'] ?? 'release';
    final depRows = DatabaseManager.db.select(
      'SELECT * FROM deployments WHERE flavor = ? AND visible = 1 ORDER BY created_at DESC LIMIT 1',
      [flavor],
    );
    if (depRows.isEmpty) {
      return Response.ok(jsonEncode({'deployment': null, 'update': null}),
          headers: {'content-type': 'application/json'});
    }
    final deployment = depRows.first;
    final depIdStr = deployment['id'].toString();
    final postRows = DatabaseManager.db.select(
        'SELECT * FROM posts WHERE type = ? AND deploymentId = ? ORDER BY created_at DESC LIMIT 1',
        ['changelog', depIdStr]);
    final update = postRows.isNotEmpty ? postRows.first : null;
    return Response.ok(jsonEncode({'deployment': deployment, 'update': update}),
        headers: {'content-type': 'application/json'});
  } catch (e) {
    return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'});
  }
}
