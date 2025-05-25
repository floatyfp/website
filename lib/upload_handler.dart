import 'dart:io';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';
import 'dart:typed_data';
import 'session_manager.dart';
import 'dart:isolate';

/// Handler for raw file uploads via '?filename=' query param and raw body.
Future<Response> uploadFileHandler(Request req) async {
  print('handler in isolate: ${Isolate.current.hashCode}');
  // Auth: ensure valid editor session
  final sessionId = req.url.queryParameters['sessionId'];
  if (sessionId == null || SessionManager.getData(sessionId) == null) {
    return Response.forbidden(jsonEncode({'error': 'Invalid session'}),
        headers: {'content-type': 'application/json'});
  }
  final filenameRaw = req.url.queryParameters['filename'];
  if (filenameRaw == null || filenameRaw.isEmpty) {
    return Response(400,
        body: jsonEncode({'error': 'Missing filename query parameter'}),
        headers: {'content-type': 'application/json'});
  }
  // Read all body bytes
  final bytes = await req.read().fold<BytesBuilder>(BytesBuilder(), (b, d) {
    b.add(d);
    return b;
  }).then((b) => b.takeBytes());

  // Ensure upload directory exists
  final dir = Directory('data/uploads');
  if (!dir.existsSync()) dir.createSync(recursive: true);

  // Generate unique filename
  final ext = filenameRaw.contains('.')
      ? filenameRaw.substring(filenameRaw.lastIndexOf('.'))
      : '';
  final id = Uuid().v4();
  final filename = '$id$ext';
  final outFile = File('${dir.path}/$filename');
  await outFile.writeAsBytes(bytes);

  final urlPath = '/media/$filename';
  return Response.ok(jsonEncode({'url': urlPath}),
      headers: {'content-type': 'application/json'});
}
