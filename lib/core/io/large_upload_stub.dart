import 'package:dio/dio.dart';
import 'package:intellipilot/core/io/large_upload.dart';

class _StubLargeUploader implements LargeUploader {
  const _StubLargeUploader();

  @override
  bool get isSupported => false;

  @override
  Future<PickedUpload?> pick({String? accept}) async => null;

  @override
  Future<UploadResponse> send({
    required String url,
    required PickedUpload file,
    required Map<String, String> headers,
    String fieldName = 'file',
    bool withCredentials = false,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) => throw UnsupportedError('Large uploads are not supported here');
}

LargeUploader createLargeUploader() => const _StubLargeUploader();
