import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import '../lib/ws_handler.dart';
import '../lib/post_handler.dart';
import '../lib/upload_handler.dart';
import '../lib/session_manager.dart';
import '../lib/deploy_handler.dart';
import '../lib/get_deployments_handler.dart';
import '../lib/platform_channel_matrix_handler.dart';
import '../lib/database.dart';

void main() async {
  // Initialize SQLite database
  DatabaseManager.init();
  // Start periodic scheduler to release posts
  DatabaseManager.startScheduler();

  var router = Router();

  // WebSocket endpoint
  router.all('/ws', wsHandler());
  // Deploy endpoint
  router.post('/api/deploy', deployHandler);
  // Editor submit endpoint (handles auth in handler)
  router.post('/api/editor/submit', publishHandler);
  // File upload endpoint
  router.post('/api/upload', uploadFileHandler);
  // Get all published posts
  router.get('/api/posts', getAllPostsHandler);
  // Get deployments (new)
  router.get('/api/deployments', getDeploymentsHandler);
  // Get platform/channel matrix
  router.get('/api/platform-channel-matrix', platformChannelMatrixHandler);
  // Get session metadata
  router.get('/api/session-metadata', sessionMetadataHandler);
  // Get latest update
  router.get('/api/latest-update', latestUpdateHandler);
  // Serve uploaded media
  router.mount(
    '/media/',
    createStaticHandler('data/uploads',
        serveFilesOutsidePath: false, listDirectories: false),
  );
  router.mount(
    '/download/media',
    createStaticHandler('files',
        serveFilesOutsidePath: false, listDirectories: false),
  );
  // Fetch post content by slug
  router.get('/api/post/<slug>', getPostBySlugHandler);

  // Helper function to serve SPA
  Response _serveSpa() {
    final file = File('web/spa.html');
    if (!file.existsSync()) {
      return Response.notFound('spa.html not found');
    }
    final bytes = file.readAsBytesSync();
    return Response.ok(bytes, headers: {'content-type': 'text/html'});
  }

  // Serve /editor as editor.html (keeping separate from SPA)
  router.all('/editor', (Request req) {
    final id = req.requestedUri.queryParameters['id'];
    if (id == null || SessionManager.getData(id) == null) {
      return Response.forbidden('Invalid or expired session');
    }
    final file = File('web/editor.html');
    if (!file.existsSync()) {
      return Response.notFound('editor.html not found');
    }
    final bytes = file.readAsBytesSync();
    return Response.ok(bytes, headers: {'content-type': 'text/html'});
  });

  // Serve SPA routes
  List<String> spaRoutes = ['/', '/blog', '/download', '/changelogs'];
  for (final route in spaRoutes) {
    router.all(route, (Request req) {
      return _serveSpa();
    });
  }

  // Handle post slug routes for SPA
  router.all('/post/<slug>', (Request req, String slug) {
    return _serveSpa();
  });
  // All API and WebSocket routes must be registered BEFORE static file handler!
  // (This ensures /ws and /api are always reachable, even if the file doesn't exist)

  // Serve static files (index.html, editor.html, etc.) from /web
  final staticHandler =
      createStaticHandler('web', defaultDocument: 'index.html');
  router.all('/<_|.*>', staticHandler);

  // Error page middleware
  Response errorPage(Response res) {
    if (res.statusCode == 200) return res;
    final errorHtml = File('web/error.html')
        .readAsStringSync()
        .replaceAll('{code}', res.statusCode.toString())
        .replaceAll(
            '{message}',
            res.statusCode == 403
                ? 'Unauthorized'
                : res.statusCode == 404
                    ? 'Not Found'
                    : 'Error');
    return Response(res.statusCode,
        body: errorHtml, headers: {'content-type': 'text/html'});
  }

  var handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware((innerHandler) => (Request req) async {
            final res = await innerHandler(req);
            if (res.statusCode == 403 || res.statusCode == 404) {
              return errorPage(res);
            }
            return res;
          })
      .addHandler(router);

  final env = DotEnv(includePlatformEnvironment: true)..load();

  var server = await shelf_io.serve(
      handler, InternetAddress.anyIPv4, int.parse(env['PORT'] ?? '8080'),
      shared: true);
  print('Serving at http://${server.address.host}:${server.port}');
}
