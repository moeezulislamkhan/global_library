import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'book.dart';

class LocalBookStorage {
  LocalBookStorage({
    http.Client? client,
    Future<Directory> Function()? documentsDirectory,
  })  : _client = client ?? http.Client(),
        _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory;

  static const _maxFileBytes = 50 * 1024 * 1024;
  final http.Client _client;
  final Future<Directory> Function() _documentsDirectory;

  Future<File> download(
    Book book,
    String format, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    final url = format == 'epub' ? book.epubUrl : book.pdfUrl;
    final uri = url == null ? null : Uri.tryParse(url);
    if (!_isAuthorizedSource(uri)) {
      throw const LocalBookStorageException(
        'This book does not have a supported authorized download.',
      );
    }

    final root = await _documentsDirectory();
    final directory = Directory(p.join(root.path, 'books'));
    await directory.create(recursive: true);
    final extension = format == 'epub' ? 'epub' : 'pdf';
    final sanitizedId = book.key
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final id = sanitizedId.isEmpty
        ? 'book'
        : sanitizedId.substring(
            0,
            sanitizedId.length.clamp(1, 120).toInt(),
          );
    final basename = '${id.isEmpty ? 'book' : id}.$extension';
    final target = File(p.join(directory.path, basename));
    final temporary = File(
      p.join(directory.path,
          '$basename.${DateTime.now().microsecondsSinceEpoch}.part'),
    );

    try {
      final response = await _client
          .send(http.Request('GET', uri!))
          .timeout(const Duration(seconds: 45));
      if (response.statusCode != 200) {
        throw LocalBookStorageException(
          'The book file server returned HTTP ${response.statusCode}.',
        );
      }
      if (response.contentLength != null &&
          response.contentLength! > _maxFileBytes) {
        throw const LocalBookStorageException(
          'This book file is too large to download.',
        );
      }

      final sink = temporary.openWrite();
      var downloadedBytes = 0;
      try {
        await for (final chunk
            in response.stream.timeout(const Duration(seconds: 45))) {
          downloadedBytes += chunk.length;
          if (downloadedBytes > _maxFileBytes) {
            throw const LocalBookStorageException(
              'This book file is too large to download.',
            );
          }
          sink.add(chunk);
          onProgress?.call(downloadedBytes, response.contentLength);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (downloadedBytes == 0 || !await _isValidBookFile(temporary, format)) {
        throw const LocalBookStorageException(
          'The downloaded file is empty or is not a valid book file.',
        );
      }
      if (await target.exists()) await target.delete();
      return await temporary.rename(target.path);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<bool> _isValidBookFile(File file, String format) async {
    final handle = await file.open();
    try {
      final header = await handle.read(4);
      if (format == 'pdf') {
        return header.length == 4 &&
            header[0] == 0x25 &&
            header[1] == 0x50 &&
            header[2] == 0x44 &&
            header[3] == 0x46;
      }
      return header.length >= 2 && header[0] == 0x50 && header[1] == 0x4b;
    } finally {
      await handle.close();
    }
  }

  bool _isAuthorizedSource(Uri? uri) =>
      uri != null &&
      uri.scheme == 'https' &&
      (uri.host == 'gutenberg.org' ||
          uri.host.endsWith('.gutenberg.org') ||
          uri.host == 'archive.org' ||
          uri.host.endsWith('.archive.org'));

  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  Future<void> dispose() async {
    _client.close();
  }
}

class LocalBookStorageException implements Exception {
  const LocalBookStorageException(this.message);

  final String message;

  @override
  String toString() => message;
}
