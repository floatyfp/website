import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';
import 'session_manager.dart';
import 'database.dart';

/// Handles HTTP POST /publish to submit content using a valid session.
Future<Response> publishHandler(Request req) async {
  final requestId = const Uuid().v4().substring(0, 8);
  print(
      '[$requestId] Handling publish request: ${req.method} ${req.requestedUri}');
  print('[$requestId] Headers: ${req.headers}');

  try {
    final body = await req.readAsString();
    print('[$requestId] Request body length: ${body.length}');

    if (body.isEmpty) {
      print('[$requestId] Error: Empty request body');
      return Response.badRequest(
        body: jsonEncode({'error': 'Empty request body'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final dynamic decodedJson;
    try {
      decodedJson = jsonDecode(body);
      print('[$requestId] Parsed JSON type: ${decodedJson.runtimeType}');
      if (decodedJson is Map) {
        print('[$requestId] JSON keys: ${decodedJson.keys.toList()}');
      }
    } catch (e, stackTrace) {
      print('[$requestId] Failed to parse JSON: $e');
      print('Stack trace: $stackTrace');
      return Response.badRequest(
        body: jsonEncode(
            {'error': 'Invalid JSON format', 'details': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }

    if (decodedJson is! Map<String, dynamic>) {
      print(
          '[$requestId] Error: Expected Map<String, dynamic> but got ${decodedJson.runtimeType}');
      return Response.badRequest(
        body: jsonEncode({'error': 'Expected a JSON object'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final payload = decodedJson;
    print('[$requestId] Processing payload');
    print('[$requestId] Has sessionId: ${payload.containsKey('sessionId')}');
    print('[$requestId] Type: ${payload['type']}');

    final sessionId = payload['sessionId'] as String?;
    final sessionData =
        sessionId != null ? SessionManager.getData(sessionId) : null;

    if (sessionId == null || sessionData == null) {
      print('[$requestId] Error: Invalid or missing session');
      print('[$requestId] Session ID: $sessionId');
      print('[$requestId] Session data exists: ${sessionData != null}');
      return Response.forbidden(jsonEncode({'error': 'Invalid session'}),
          headers: {'content-type': 'application/json'});
    }
    final type = sessionData.postType ?? payload['type'] as String? ?? '';
    final typeLower = type.toLowerCase();

    // Helper to check required
    bool missing(dynamic value) {
      final isMissing = value == null ||
          (value is String && value.trim().isEmpty) ||
          (value is List && value.isEmpty);
      return isMissing;
    }

    List<String> missingFields = [];
    print('[$requestId] Validating required fields for type: $typeLower');
    print('[$requestId] Title present: ${payload.containsKey('title')}');
    print('[$requestId] URL present: ${payload.containsKey('url')}');
    print('[$requestId] Content present: ${payload.containsKey('content')}');
    print('[$requestId] Summary present: ${payload.containsKey('summary')}');
    print(
        '[$requestId] Thumbnail present: ${payload.containsKey('thumbnail')}');
    print('[$requestId] Author present: ${payload.containsKey('author')}');

    // Parse all possible fields
    final title = payload['title'] as String?;
    final url = payload['url'] as String?;
    final content = payload['content'] as String?;
    final summary = payload['summary'] as String?;
    final tags = (payload['tags'] as List<dynamic>?);
    final thumbnail = payload['thumbnail'] as String?;
    final dropdownsRaw = payload['dropdowns'];

    final author = payload['author'] as String?;

    // Validate required fields by type
    if (typeLower == 'blog') {
      if (missing(title)) missingFields.add('title');
      if (missing(url)) missingFields.add('url');
      if (missing(content)) missingFields.add('content');
      if (missing(summary)) missingFields.add('summary');

      if (missing(thumbnail)) missingFields.add('thumbnail');
      if (missing(author)) missingFields.add('author');
    } else if (typeLower == 'changelog') {
      if (missing(title)) missingFields.add('title');
      if (missing(summary)) missingFields.add('summary');

      if (missing(thumbnail)) missingFields.add('thumbnail');
      // content and dropdowns are optional for changelog
    } else {
      if (missing(title)) missingFields.add('title');
      if (missing(url)) missingFields.add('url');
      if (missing(content)) missingFields.add('content');
      if (missing(summary)) missingFields.add('summary');

      if (missing(thumbnail)) missingFields.add('thumbnail');
      if (missing(author)) missingFields.add('author');
      // dropdowns optional
    }
    if (missingFields.isNotEmpty) {
      print('[$requestId] Error: Missing required fields: $missingFields');
      print('[$requestId] Post type: $typeLower');
      return Response(400,
          body: jsonEncode(
              {'error': 'Missing required fields', 'fields': missingFields}),
          headers: {'content-type': 'application/json'});
    }

    // Handle tags as List<Map<String, dynamic>>
    List<Map<String, dynamic>>? tagsList;
    if (tags != null) {
      tagsList = tags
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    final dropdowns = dropdownsRaw;
    final urlVal = url ?? '';
    final contentVal = content ?? '';
    final summaryVal = summary ?? '';
    final thumbnailVal = thumbnail ?? '';

    final authorVal = author ?? '';

    final createdAtStr =
        payload['createdAt'] as String? ?? DateTime.now().toIso8601String();
    final createdAt = DateTime.parse(createdAtStr);

    String postId;
    if (sessionData.mode == 'edit' && sessionData.postId != null) {
      postId = sessionData.postId!;
      print('Updating post $postId: $title');
    } else {
      postId = Uuid().v4();
      print('Creating post $postId: $title');
    }
    if (type == 'blog' && url != null && url.isNotEmpty) {
      print('[$requestId] Checking for duplicate blog URL: $url');
      final slugRows = DatabaseManager.db
          .select('SELECT id FROM posts WHERE url = ?', [url]);
      final isDuplicate = slugRows.isNotEmpty &&
          (sessionData.mode != 'edit' || slugRows.first['id'] != postId);

      if (isDuplicate) {
        print('[$requestId] Error: Duplicate blog URL detected');
        print('[$requestId] URL: $url');
        print(
            '[$requestId] Existing ID: ${slugRows.isNotEmpty ? slugRows.first['id'] : null}');
        print('[$requestId] Current post ID: $postId');
        print('[$requestId] Mode: ${sessionData.mode}');
        return Response(409,
            body: jsonEncode(
                {'error': 'A blog post with this URL slug already exists.'}),
            headers: {'content-type': 'application/json'});
      } else {
        print('[$requestId] No duplicate URL found');
      }
    }
    // Consume session
    print('[$requestId] Validating session: $sessionId');
    SessionManager.validate(sessionId);
    print('[$requestId] Session validated successfully');

    try {
      String versionVal = '';
      String flavorVal = '';
      int? deploymentIdVal;

      if (typeLower == 'changelog') {
        print('[$requestId] Processing changelog post');
        print('[$requestId] Metadata: ${sessionData.metadata}');
        print('[$requestId] Mode: ${sessionData.mode}');
        print('[$requestId] Post ID: $postId');

        // For edit mode, first get existing values from the database
        if (sessionData.mode == 'edit' && sessionData.postId != null) {
          final existingPost = DatabaseManager.db.select(
            'SELECT version, flavor, deploymentId FROM posts WHERE id = ?',
            [sessionData.postId],
          );

          if (existingPost.isNotEmpty) {
            versionVal = (sessionData.metadata != null &&
                    sessionData.metadata!['version'] != null)
                ? sessionData.metadata!['version'].toString()
                : existingPost.first['version']?.toString() ?? '';

            flavorVal = (sessionData.metadata != null &&
                    sessionData.metadata!['flavor'] != null)
                ? sessionData.metadata!['flavor'].toString()
                : existingPost.first['flavor']?.toString() ?? '';

            deploymentIdVal = (sessionData.metadata != null &&
                    sessionData.metadata!['deploymentId'] != null)
                ? int.parse(sessionData.metadata!['deploymentId'].toString())
                : existingPost.first['deploymentId'] as int?;

            print(
                '[$requestId] Using existing values - Version: $versionVal, Flavor: $flavorVal, DeploymentId: $deploymentIdVal');
          }
        } else {
          // For new posts, use the values from metadata
          versionVal = (sessionData.metadata != null &&
                  sessionData.metadata!['version'] != null)
              ? sessionData.metadata!['version'].toString()
              : '';
          flavorVal = (sessionData.metadata != null &&
                  sessionData.metadata!['flavor'] != null)
              ? sessionData.metadata!['flavor'].toString()
              : '';
          deploymentIdVal = (sessionData.metadata != null &&
                  sessionData.metadata!['deploymentId'] != null)
              ? int.parse(sessionData.metadata!['deploymentId'].toString())
              : null;
        }
      }

      // Schedule entire post for release (do NOT delete previous changelogs)
      print('[$requestId] Scheduling post');
      print('[$requestId] Post ID: $postId');
      print('[$requestId] Type: $type');
      print('[$requestId] Title: $title');
      print('[$requestId] URL: ${typeLower == 'changelog' ? postId : urlVal}');
      print('[$requestId] Content length: ${contentVal.length}');
      print('[$requestId] Has thumbnail: ${thumbnailVal.isNotEmpty}');
      print('[$requestId] Tags count: ${tagsList?.length ?? 0}');
      if (typeLower == 'changelog') {
        print('[$requestId] Version: $versionVal');
        print('[$requestId] Flavor: $flavorVal');
        print('[$requestId] Deployment ID: $deploymentIdVal');
      }

      DatabaseManager.schedulePost(
        id: postId,
        url: typeLower == 'changelog' ? postId : urlVal,
        type: type,
        title: title ?? '',
        content: contentVal,
        summary: summaryVal,
        tags: tagsList,
        thumbnail: thumbnailVal,
        dropdowns: dropdowns,
        version: typeLower == 'changelog' ? versionVal : '',
        flavor: typeLower == 'changelog' ? flavorVal : '',
        deploymentId: deploymentIdVal,
        author: typeLower == 'changelog' ? '' : authorVal,
        scheduledAt: createdAt,
      );

      print('[$requestId] Successfully scheduled post');
      print('[$requestId] Post ID: $postId');
      print('[$requestId] Type: $type');
      print('[$requestId] URL: ${typeLower == 'changelog' ? postId : urlVal}');

      if (typeLower == 'changelog' && deploymentIdVal != null) {
        print('[$requestId] Marking deployment as visible');
        print('[$requestId] Deployment ID: $deploymentIdVal');
        print('[$requestId] Version: $versionVal');
        print('[$requestId] Flavor: $flavorVal');

        DatabaseManager.markDeploymentVisible(deploymentId: deploymentIdVal);
        print('[$requestId] Deployment marked as visible: $deploymentIdVal');
      }
    } catch (e) {
      print(e);
      return Response.internalServerError(
          body: jsonEncode({'error': 'Invalid payload'}),
          headers: {'content-type': 'application/json'});
    }

    final responseUrl = '/posts/$postId';
    print('[$requestId] Successfully processed request');
    print('[$requestId] Response URL: $responseUrl');

    return Response.ok(
      jsonEncode({'status': 'ok', 'url': responseUrl}),
      headers: {'content-type': 'application/json'},
    );
  } catch (e, stackTrace) {
    print('[$requestId] Error in publishHandler: $e');
    print('Stack trace: $stackTrace');

    return Response.internalServerError(
      body: jsonEncode({
        'error': 'Internal server error',
        'requestId': requestId,
        'details': e.toString(),
      }),
      headers: {
        'content-type': 'application/json',
        'X-Request-ID': requestId,
      },
    );
  }
}

/// Handler for GET /api/posts to retrieve all published posts, sorted by date descending.
Future<Response> getAllPostsHandler(Request req) async {
  try {
    final typeFilter = req.url.queryParameters['type'];
    final rows = DatabaseManager.db.select(
      typeFilter != null && typeFilter.isNotEmpty
          ? 'SELECT * FROM posts WHERE type = ? ORDER BY created_at DESC'
          : 'SELECT * FROM posts ORDER BY created_at DESC',
      typeFilter != null && typeFilter.isNotEmpty ? [typeFilter] : [],
    );
    final posts = rows.map((row) {
      final type = row['type'] as String;
      final title = row['title'] as String;
      final summary = row['summary'] as String;
      final createdAt = row['created_at'] as String;
      List<Map<String, dynamic>> tags = [];
      if (row['tags'] != null) {
        try {
          final parsed = jsonDecode(row['tags'] as String);
          if (parsed is List) {
            tags = parsed
                .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
                .toList();
          }
        } catch (_) {}
      }
      final dateObj = DateTime.tryParse(createdAt);
      String formattedDate;
      if (dateObj != null) {
        formattedDate =
            '${dateObj.day} ${_monthName(dateObj.month)} ${dateObj.year.toString().substring(2)}';
      } else {
        formattedDate = createdAt;
      }
      return {
        'type': type,
        'title': title,
        'summary': summary,
        'date': formattedDate,
        'tags': tags,
        'thumbnail': row['thumbnail'] as String,
        'dropdowns': row['dropdowns'] != null
            ? List<dynamic>.from(jsonDecode(row['dropdowns'] as String))
            : <dynamic>[],
        'content': row['content'] as String,
        'version': row['version'] as String? ?? '',
        'flavor': row['flavor'] as String? ?? '',
        'author': row['author'] as String? ?? '',
        'url': row['url'] as String,
        'createdAt': row['created_at'] as String,
        'deploymentId': row['deploymentId']?.toString() ?? '',
      };
    }).toList();
    return Response.ok(jsonEncode({'posts': posts}),
        headers: {'content-type': 'application/json'});
  } catch (_) {
    return Response.internalServerError(
        body: jsonEncode({'error': 'Could not fetch posts'}),
        headers: {'content-type': 'application/json'});
  }
}

String _monthName(int month) {
  const months = [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];
  return months[month];
}

/// Handler for GET /api/post/<slug> to fetch a single post by its url slug
Future<Response> getPostBySlugHandler(Request req, String slug) async {
  try {
    final rows =
        DatabaseManager.db.select('SELECT * FROM posts WHERE url = ?', [slug]);
    if (rows.isEmpty) {
      return Response.notFound(jsonEncode({'error': 'Post not found'}),
          headers: {'content-type': 'application/json'});
    }
    final row = rows.first;
    List<Map<String, dynamic>> tags = [];
    if (row['tags'] != null) {
      try {
        final parsed = jsonDecode(row['tags'] as String);
        if (parsed is List) {
          tags = parsed
              .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (_) {}
    }
    final createdAt = row['created_at'] as String;
    final dateObj = DateTime.tryParse(createdAt);
    String formattedDate;
    if (dateObj != null) {
      formattedDate =
          '${dateObj.day} ${_monthName(dateObj.month)} ${dateObj.year.toString().substring(2)}';
    } else {
      formattedDate = createdAt;
    }
    final post = {
      'type': row['type'] as String,
      'title': row['title'] as String,
      'summary': row['summary'] as String,
      'content': row['content'] as String,
      'date': formattedDate,
      'tags': tags,
      'thumbnail': row['thumbnail'] as String,
      'dropdowns': row['dropdowns'] != null
          ? List<dynamic>.from(jsonDecode(row['dropdowns'] as String))
          : <dynamic>[],
      'version': row['version'] as String? ?? '',
      'author': row['author'] as String? ?? '',
      'url': row['url'] as String,
      'createdAt': row['created_at'] as String,
    };
    return Response.ok(jsonEncode(post),
        headers: {'content-type': 'application/json'});
  } catch (e) {
    return Response.internalServerError(
        body: jsonEncode({'error': 'Could not fetch post'}),
        headers: {'content-type': 'application/json'});
  }
}
