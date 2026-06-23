import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:intellipilot/core/io/file_downloader.dart';
import 'package:web/web.dart' as web;

class _WebDownloader implements FileDownloader {
  const _WebDownloader();

  @override
  bool get canDownload => true;

  @override
  Future<bool> download({
    required String filename,
    required String mimeType,
    required String contents,
  }) => downloadBytes(
    filename: filename,
    mimeType: mimeType,
    bytes: utf8.encode(contents),
  );

  @override
  Future<bool> downloadBytes({
    required String filename,
    required String mimeType,
    required List<int> bytes,
  }) async {
    final blob = web.Blob(
      [Uint8List.fromList(bytes).toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = filename
      ..style.display = 'none';
    web.document.body!.appendChild(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
    return true;
  }
}

FileDownloader createFileDownloader() => const _WebDownloader();
