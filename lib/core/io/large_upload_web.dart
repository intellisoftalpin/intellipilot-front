import 'dart:async';
import 'dart:js_interop';

import 'package:dio/dio.dart';
import 'package:intellipilot/core/io/large_upload.dart';
import 'package:web/web.dart' as web;

/// Keeps the browser `File` behind a Dart type, so reading it back is an
/// ordinary type check rather than a cast to a JS interop type.
class _WebFile {
  const _WebFile(this.file);
  final web.File file;
}

class _WebLargeUploader implements LargeUploader {
  const _WebLargeUploader();

  @override
  bool get isSupported => true;

  @override
  Future<PickedUpload?> pick({String? accept}) {
    final completer = Completer<PickedUpload?>();
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..style.display = 'none';
    if (accept != null) input.accept = accept;

    input.onChange.listen((_) {
      final files = input.files;
      input.remove();
      if (files == null || files.length == 0) {
        completer.complete(null);
        return;
      }
      final file = files.item(0)!;
      completer.complete(
        PickedUpload(
          name: file.name,
          sizeBytes: file.size,
          contentType: file.type.isEmpty ? null : file.type,
          handle: _WebFile(file),
        ),
      );
    });
    // Closing the dialog without a choice fires `cancel`, where supported.
    input.addEventListener(
      'cancel',
      (web.Event _) {
        input.remove();
        if (!completer.isCompleted) completer.complete(null);
      }.toJS,
    );

    web.document.body!.appendChild(input);
    input.click();
    return completer.future;
  }

  @override
  Future<UploadResponse> send({
    required String url,
    required PickedUpload file,
    required Map<String, String> headers,
    String fieldName = 'file',
    bool withCredentials = false,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) {
    final completer = Completer<UploadResponse>();
    if (cancelToken?.isCancelled ?? false) {
      return Future.error(const UploadCancelledException());
    }
    final xhr = web.XMLHttpRequest()
      ..open('POST', url)
      ..withCredentials = withCredentials;
    headers.forEach(xhr.setRequestHeader);

    if (onProgress != null) {
      xhr.upload.onprogress = (web.ProgressEvent e) {
        onProgress(e.loaded, e.lengthComputable ? e.total : file.sizeBytes);
      }.toJS;
    }
    xhr
      ..onload = (web.Event _) {
        if (!completer.isCompleted) {
          completer.complete(
            UploadResponse(status: xhr.status, body: xhr.responseText),
          );
        }
      }.toJS
      ..onerror = (web.Event _) {
        if (!completer.isCompleted) {
          completer.completeError(
            StateError('Upload failed: network error'),
          );
        }
      }.toJS
      ..onabort = (web.Event _) {
        if (!completer.isCompleted) {
          completer.completeError(const UploadCancelledException());
        }
      }.toJS;

    unawaited(cancelToken?.whenCancel.then((_) => xhr.abort()));

    final form = web.FormData()
      ..append(fieldName, (file.handle as _WebFile).file, file.name);
    xhr.send(form);
    return completer.future;
  }
}

LargeUploader createLargeUploader() => const _WebLargeUploader();
