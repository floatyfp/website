import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';
import 'session_manager.dart';
import 'database.dart';

/// Handles HTTP POST /publish to submit content using a valid session.
Future<Response> publishHandler(Request req) async {
  try {
    final payload =
        jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final sessionId = payload['sessionId'] as String?;
    final sessionData =
        sessionId != null ? SessionManager.getData(sessionId) : null;
    if (sessionId == null || sessionData == null) {
      return Response.forbidden(jsonEncode({'error': 'Invalid session'}),
          headers: {'content-type': 'application/json'});
    }
    final type = sessionData.postType ?? payload['type'] as String? ?? '';
    final typeLower = type.toLowerCase();

    // Helper to check required
    bool missing(dynamic value) =>
        value == null ||
        (value is String && value.trim().isEmpty) ||
        (value is List && value.isEmpty);
    List<String> missingFields = [];

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
      final slugRows = DatabaseManager.db
          .select('SELECT id FROM posts WHERE url = ?', [url]);
      final isDuplicate = slugRows.isNotEmpty &&
          (sessionData.mode != 'edit' || slugRows.first['id'] != postId);
      if (isDuplicate) {
        return Response(409,
            body: jsonEncode(
                {'error': 'A blog post with this URL slug already exists.'}),
            headers: {'content-type': 'application/json'});
      }
    }
    // Consume session
    SessionManager.validate(sessionId);

    try {
      String versionVal = '';
      String flavorVal = '';
      int? deploymentIdVal;
      if (typeLower == 'changelog') {
        print(sessionData.metadata);
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

      // Schedule entire post for release (do NOT delete previous changelogs)
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

      if (typeLower == 'changelog' && deploymentIdVal != null) {
        DatabaseManager.markDeploymentVisible(deploymentId: deploymentIdVal);
      }
    } catch (e) {
      print(e);
      return Response.internalServerError(
          body: jsonEncode({'error': 'Invalid payload'}),
          headers: {'content-type': 'application/json'});
    }

    return Response.ok(jsonEncode({'status': 'ok', 'url': '/posts/$postId'}),
        headers: {'content-type': 'application/json'});
  } catch (e) {
    print(e);
    return Response.internalServerError(
        body: jsonEncode({'error': 'Invalid payload'}),
        headers: {'content-type': 'application/json'});
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
