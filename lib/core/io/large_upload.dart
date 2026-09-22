import 'package:dio/dio.dart';
import 'package:intellipilot/core/io/large_upload_stub.dart'
    if (dart.library.js_interop) 'package:intellipilot/core/io/large_upload_web.dart'
    as impl;

/// A file the user picked for a potentially very large upload (recordings run
/// to gigabytes). Unlike `PickedFile` it never holds the bytes: [handle] is
/// the platform's reference to the file on disk, read only while sending.
class PickedUpload {
  const PickedUpload({
    required this.name,
    required this.sizeBytes,
    required this.handle,
    this.contentType,
  });

  final String name;
  final int sizeBytes;

  /// Advisory; the server sniffs the real type from the content.
  final String? contentType;

  /// Platform file reference (a browser `File` on web). Opaque to callers.
  final Object handle;
}

/// What the server answered to an upload.
class UploadResponse {
  const UploadResponse({required this.status, required this.body});
  final int status;
  final String body;

  bool get ok => status >= 200 && status < 300;
}

/// Thrown by [LargeUploader.send] when the upload was cancelled.
class UploadCancelledException implements Exception {
  const UploadCancelledException();
  @override
  String toString() => 'UploadCancelledException';
}

/// Picks and sends files without loading them into memory.
///
/// Dio's browser adapter collects the whole request body into one buffer
/// before handing it to `XMLHttpRequest`, which a 2 GB recording would not
/// survive. The web implementation instead gives the browser the `File`
/// itself inside a `FormData`, so it streams from disk, and reports progress
/// from `xhr.upload`. Targets without an implementation report
/// [isSupported] false and the UI hides the upload action, as it does for
/// ordinary attachments there.
abstract interface class LargeUploader {
  factory LargeUploader() => impl.createLargeUploader();

  bool get isSupported;

  /// Opens a single-file picker; [accept] is an `<input accept>` filter such
  /// as `audio/*,video/*`. Null when cancelled or unsupported.
  Future<PickedUpload?> pick({String? accept});

  /// POSTs [file] as the multipart field [fieldName] to the absolute [url].
  ///
  /// Throws [UploadCancelledException] once [cancelToken] is cancelled, and
  /// rethrows transport failures; any HTTP status comes back as a response.
  Future<UploadResponse> send({
    required String url,
    required PickedUpload file,
    required Map<String, String> headers,
    String fieldName = 'file',
    bool withCredentials = false,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  });
}
