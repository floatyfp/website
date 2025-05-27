import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:sqlite3/sqlite3.dart';
import 'ws_handler.dart';

/// Manages SQLite database for posts and scheduling.
class DatabaseManager {
  static late final Database db;
  static bool isInitialized = false;

  /// Initialize and create tables.
  static void init() {
    isInitialized = true;
    final dir = Directory('data');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final path = '${dir.path}/blog.db';
    db = sqlite3.open(path);
    _createTables();
  }

  static bool isDBInitialized() => isInitialized;

  static void _createTables() {
    db.execute('''
      CREATE TABLE IF NOT EXISTS deployments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        version TEXT NOT NULL,
        flavor TEXT NOT NULL,
        info_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        visible INTEGER NOT NULL DEFAULT 0,
        required INTEGER NOT NULL DEFAULT 0
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS sessions(
        id TEXT PRIMARY KEY,
        mode TEXT NOT NULL,
        postId TEXT,
        postType TEXT,
        expiresAt TEXT NOT NULL,
        metadata TEXT
      );
    ''');
    // Published posts
    db.execute('''
      CREATE TABLE IF NOT EXISTS posts(
        id TEXT PRIMARY KEY,
        url TEXT NOT NULL UNIQUE,
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        summary TEXT NOT NULL,
        tags TEXT,
        thumbnail TEXT NOT NULL,
        dropdowns TEXT,
        version TEXT NOT NULL DEFAULT '',
        author TEXT NOT NULL DEFAULT '',
        flavor TEXT,
        deploymentId INTEGER,
        created_at TEXT NOT NULL
      );
    ''');
    // Scheduled posts
    db.execute('''
      CREATE TABLE IF NOT EXISTS scheduled_posts(
        id TEXT PRIMARY KEY,
        url TEXT NOT NULL UNIQUE,
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        summary TEXT NOT NULL,
        tags TEXT,
        thumbnail TEXT NOT NULL,
        dropdowns TEXT,
        version TEXT NOT NULL DEFAULT '',
        author TEXT NOT NULL DEFAULT '',
        flavor TEXT,
        deploymentId INTEGER,
        scheduled_at TEXT NOT NULL
      );
    ''');
  }

  /// Insert or update a post record.
  static void upsertPost({
    required String id,
    required String url,
    required String type,
    required String title,
    required String content,
    required String summary,
    List<Map<String, dynamic>>? tags,
    required String thumbnail,
    List<dynamic>? dropdowns,
    String version = '',
    String flavor = '',
    int? deploymentId,
    String author = '',
    required DateTime createdAt,
  }) {
    final tagsJson = tags != null ? jsonEncode(tags) : null;
    final dropdownsJson = dropdowns != null ? jsonEncode(dropdowns) : null;
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO posts(
        id, url, type, title, content, summary, tags, thumbnail, dropdowns, version, author, flavor, deploymentId, created_at
      ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    ''');
    stmt.execute([
      id,
      url,
      type,
      title,
      content,
      summary,
      tagsJson,
      thumbnail,
      dropdownsJson,
      version,
      author,
      flavor,
      deploymentId,
      createdAt.toIso8601String(),
    ]);
    stmt.dispose();
    final env = DotEnv(includePlatformEnvironment: true)..load();
    // Notify all connected websocket clients about the new changelog session
    for (final socket in globalWebSocketClients.values) {
      socket.sink.add(jsonEncode({
        'type': 'notification',
        'id': type == 'changelog'
            ? env['CHANGELOG_CHANNEL_ID']
            : env['BLOG_CHANNEL_ID'],
        'textString':
            '<@&${type == 'changelog' ? env['CHANGELOG_ROLE_ID'] : env['BLOG_ROLE_ID']}>',
        'title': 'New ${type == 'changelog' ? 'changelog' : 'post'}: $title',
        'description': summary,
        'image': 'https://floaty.fyi$thumbnail',
        'button': true,
        'buttonText': 'Read more',
        'buttonUrl': type == 'changelog'
            ? 'https://floaty.fyi/changelogs#${id}'
            : 'https://floaty.fyi/post/${url}',
      }));
    }
  }

  /// Schedule a post for future release.
  static void schedulePost({
    required String id,
    required String url,
    required String type,
    required String title,
    required String content,
    required String summary,
    List<Map<String, dynamic>>? tags,
    required String thumbnail,
    List<dynamic>? dropdowns,
    String version = '',
    String flavor = '',
    int? deploymentId,
    String author = '',
    required DateTime scheduledAt,
  }) {
    final now = DateTime.now();
    // If scheduled time is now or past, publish immediately
    if (!scheduledAt.isAfter(now)) {
      upsertPost(
        id: id,
        url: url,
        type: type,
        title: title,
        content: content,
        summary: summary,
        tags: tags,
        thumbnail: thumbnail,
        dropdowns: dropdowns,
        version: version,
        deploymentId: deploymentId,
        flavor: flavor,
        author: author,
        createdAt: scheduledAt,
      );
      // DatabaseManager.markDeploymentVisible(deploymentId: deploymentId!);
      return;
    }
    // Otherwise, insert into scheduled_posts
    final tagsJson = tags != null ? jsonEncode(tags) : null;
    final dropdownsJson = dropdowns != null ? jsonEncode(dropdowns) : null;
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO scheduled_posts(
        id, url, type, title, content, summary, tags, thumbnail, dropdowns, version, author, flavor, deploymentId, scheduled_at
      ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    ''');
    stmt.execute([
      id,
      url,
      type,
      title,
      content,
      summary,
      tagsJson,
      thumbnail,
      dropdownsJson,
      version,
      author,
      flavor,
      deploymentId,
      scheduledAt.toIso8601String(),
    ]);
    stmt.dispose();
  }

  /// Insert a deployment record.
  static int insertDeployment({
    required String version,
    required String flavor,
    required String infoJson,
    required DateTime createdAt,
    bool visible = false,
  }) {
    final stmt = db.prepare('''
      INSERT INTO deployments(version, flavor, info_json, created_at, visible)
      VALUES (?, ?, ?, ?, ?)
    ''');
    stmt.execute([
      version,
      flavor,
      infoJson,
      createdAt.toIso8601String(),
      visible ? 1 : 0,
    ]);
    final id = db.lastInsertRowId;
    stmt.dispose();
    return id;
  }

  /// Periodically release scheduled posts to published posts.
  static void startScheduler() {
    Timer.periodic(Duration(minutes: 1), (_) {
      final now = DateTime.now().toIso8601String();
      final rows = db.select(
          'SELECT * FROM scheduled_posts WHERE scheduled_at <= ?', [now]);
      final deleteStmt = db.prepare('DELETE FROM scheduled_posts WHERE id = ?');
      for (final row in rows) {
        // Move to posts
        upsertPost(
          id: row['id'] as String,
          url: row['url'] as String,
          type: row['type'] as String,
          title: row['title'] as String,
          content: row['content'] as String,
          summary: row['summary'] as String,
          tags: row['tags'] != null
              ? (jsonDecode(row['tags'] as String) as List)
                  .map<Map<String, dynamic>>(
                      (e) => Map<String, dynamic>.from(e))
                  .toList()
              : null,
          thumbnail: row['thumbnail'] as String,
          dropdowns: row['dropdowns'] != null
              ? List<dynamic>.from(jsonDecode(row['dropdowns'] as String))
              : null,
          flavor: row['flavor'] != null ? row['flavor'] as String : '',
          version: row['version'] != null ? row['version'] as String : '',
          deploymentId: row['deploymentId'],
          author: row['author'] != null ? row['author'] as String : '',
          createdAt: DateTime.parse(row['scheduled_at'] as String),
        );
        deleteStmt.execute([row['id'] as String]);

        if (row['type'] == 'changelog' && row['deploymentId'] != null) {
          markDeploymentVisible(deploymentId: row['deploymentId'] as int);
        }
      }
      deleteStmt.dispose();
    });
  }

  /// Mark a deployment as visible when a changelog is submitted.
  static void markDeploymentVisible({required int deploymentId}) {
    final stmt = db.prepare('UPDATE deployments SET visible = 1 WHERE id = ?');
    stmt.execute([deploymentId]);
    stmt.dispose();
    // Notify all connected websocket clients about the new changelog session
    final env = DotEnv(includePlatformEnvironment: true)..load();
    final rows =
        db.select('SELECT * FROM deployments WHERE id = ?', [deploymentId]);
    final row = rows.first;
    for (final socket in globalWebSocketClients.values) {
      socket.sink.add(jsonEncode({
        'type': 'notification',
        'id': env['DEPLOY_CHANNEL_ID'],
        'textString': '<@&${env['DEPLOY_ROLE_ID']}>',
        'title':
            'New Deployment: ${row['flavor'].toString()} v${row['version'].toString()}',
        'description':
            'Click the button below to see the changelog for more details',
        'button': true,
        'buttonText': 'Read changelog',
        'buttonUrl': 'https://floaty.fyi/changelogs#$deploymentId',
      }));
    }
  }
}
