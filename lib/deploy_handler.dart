import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:shelf/shelf.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:dotenv/dotenv.dart';
import 'package:mime/mime.dart';
import 'database.dart';
import 'ws_handler.dart';
import 'session_manager.dart';

/// Handles POST /api/deploy for deployment uploads.
Future<Response> deployHandler(Request req) async {
  try {
    // Authenticate with x-api-key header (same as WS)
    final env = DotEnv(includePlatformEnvironment: true)..load();
    final expected = env['WS_PASSWORD'] ?? 'changeme';
    final apiKey = req.headers['x-api-key'];
    if (apiKey != expected) {
      return Response.forbidden(jsonEncode({'error': 'Invalid API key'}),
          headers: {'content-type': 'application/json'});
    }

    // Parse multipart form
    final contentType = req.headers['content-type'] ?? '';
    if (!contentType.contains('multipart')) {
      return Response(400,
          body: jsonEncode({'error': 'Expected multipart/form-data'}),
          headers: {'content-type': 'application/json'});
    }
    final boundary =
        RegExp(r'boundary=(.*)').firstMatch(contentType)?.group(1) ?? '';
    final fields = <String, List<int>>{};
    final fieldStrings = <String, String>{};
    final files = <String, List<int>>{};
    final transformer = MimeMultipartTransformer(boundary);
    await for (final part in transformer.bind(req.read())) {
      final contentDisposition = part.headers['content-disposition'] ?? '';
      final nameMatch =
          RegExp(r'name="([^"]+)"').firstMatch(contentDisposition);
      if (nameMatch != null) {
        final name = nameMatch.group(1)!;
        final content = await part.toList();
        final bytes = content.expand((e) => e).toList();
        // Check if this is a file or a field
        if (contentDisposition.contains('filename=')) {
          files[name] = bytes;
        } else {
          fieldStrings[name] = utf8.decode(bytes);
          fields[name] = bytes;
        }
      }
    }
    // Only require 'artifact' (ZIP)
    if (!files.containsKey('artifact')) {
      return Response(400,
          body: jsonEncode({'error': 'Missing artifact (ZIP)'}),
          headers: {'content-type': 'application/json'});
    }
    // Extract ZIP to temp dir
    final tmpDir = Directory.systemTemp.createTempSync('deploy_');
    final archive = ZipDecoder().decodeBytes(files['artifact']!);
    for (final file in archive) {
      if (file.isFile) {
        final outPath = p.join(tmpDir.path, file.name);
        File(outPath).createSync(recursive: true);
        File(outPath).writeAsBytesSync(file.content as List<int>);
      }
    }
    // Read info.json from extracted files
    final infoFile = File(p.join(tmpDir.path, 'info.json'));
    if (!infoFile.existsSync()) {
      tmpDir.deleteSync(recursive: true);
      return Response(400,
          body: jsonEncode({'error': 'info.json missing from ZIP'}),
          headers: {'content-type': 'application/json'});
    }
    final infoJson = infoFile.readAsStringSync();
    Map<String, dynamic> info;
    try {
      info = jsonDecode(infoJson) as Map<String, dynamic>;
    } catch (e) {
      tmpDir.deleteSync(recursive: true);
      return Response(400,
          body: jsonEncode({'error': 'Invalid info.json: $e'}),
          headers: {'content-type': 'application/json'});
    }
    final version = info['version'] as String?;
    final flavor = info['flavor'] as String?;

    final platforms = info['platforms'] as List?;
    if (version == null || flavor == null || platforms == null) {
      tmpDir.deleteSync(recursive: true);
      return Response(400,
          body: jsonEncode(
              {'error': 'Missing version, flavor, or platforms in info.json'}),
          headers: {'content-type': 'application/json'});
    }

    // For each platform, move files to correct place and rename as needed
    final extracted = <String, List<String>>{};
    final updatedPlatforms = [];
    for (final plat in platforms) {
      final platform = plat['platform'] as String?;
      final fileList = plat['files'] as List?;
      if (platform == null || fileList == null) continue;
      final saveDir = Directory(p.join('files', platform, version));
      if (!saveDir.existsSync()) saveDir.createSync(recursive: true);
      extracted[platform] = [];
      final updatedFiles = [];
      for (final fileDesc in fileList) {
        final relPath = fileDesc['path'] as String?;
        final fileType = fileDesc['type'] as String?;
        if (relPath == null) continue;
        final srcFile = File(p.join(tmpDir.path, relPath));
        if (!srcFile.existsSync()) {
          return Response(400,
              body: jsonEncode(
                  {'error': 'Missing file in ZIP: $relPath for $platform'}),
              headers: {'content-type': 'application/json'});
        }
        // Compute new filename
        final origName = p.basename(relPath);
        String newName = origName;
        final flavorPrefix = 'floaty-$flavor-';
        if (!origName.startsWith(flavorPrefix)) {
          // Remove any existing 'floaty-*-' prefix
          newName = flavorPrefix +
              origName.replaceFirst(RegExp(r'^floaty-[^-]+-'), '');
        }
        // Save as files/<platform>/<version>/<newName>
        final destFile = File(p.join('files', platform, version, newName));
        destFile.parent.createSync(recursive: true);
        srcFile.copySync(destFile.path);
        extracted[platform]!.add(p.join(platform, version, newName));
        updatedFiles.add(
            {'type': fileType, 'path': p.join(platform, version, newName)});
      }
      updatedPlatforms.add({'platform': platform, 'files': updatedFiles});
    }
    // Save updated info.json at files/<platform>/<version>/info.json for each platform
    final updatedInfo = {
      'version': version,
      'flavor': flavor,
      'platforms': updatedPlatforms
    };
    final updatedInfoJson = jsonEncode(updatedInfo);
    for (final plat in updatedPlatforms) {
      final platform = plat['platform'];
      final infoPath = p.join('files', platform, version, 'info.json');
      File(infoPath).writeAsStringSync(updatedInfoJson);
    }
    // Insert info.json into deployments table
    final deploymentId = DatabaseManager.insertDeployment(
      version: version,
      flavor: flavor,
      infoJson: updatedInfoJson,
      createdAt: DateTime.now(),
      visible: false,
    );
    // Create editor session for changelog with deploymentId in metadata
    final sessionId = SessionManager.createSession(
      mode: 'new',
      postType: 'changelog',
      metadata: {
        'version': version,
        'flavor': flavor,
        'deploymentId': deploymentId,
      },
    );
    // Notify all connected websocket clients about the new changelog session
    for (final socket in globalWebSocketClients) {
      socket.sink.add(jsonEncode({
        'type': 'changelog_session_created',
        'sessionId': sessionId,
        'deploymentId': deploymentId,
        'version': version,
        'flavor': flavor
      }));
    }
    tmpDir.deleteSync(recursive: true);
    return Response.ok(
        jsonEncode({
          'status': 'ok',
          'message': 'Deployment uploaded and extracted',
          'version': version,
          'deploymentId': deploymentId,
          'flavor': flavor,
          'platforms': extracted
        }),
        headers: {'content-type': 'application/json'});
  } catch (e, st) {
    print(e);
    print(st);
    return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'});
  }
}
