import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intellipilot/core/ui/markdown_text.dart';
import 'package:intellipilot/features/docs/domain/doc_path.dart';
import 'package:intellipilot/features/docs/domain/docs_repository.dart';

/// An image referenced by a document, fetched through the API.
///
/// Documentation blobs are not public URLs — the endpoint checks project
/// membership and enforces the same path jail as the rest of the source — so
/// they cannot be handed to `Image.network`. The bytes come back over the
/// authorized client instead, which also makes this behave identically on web
/// and on native.
///
/// A reference that climbs above the shared folder is not fetched at all; it
/// renders as a placeholder, since that content is deliberately not served.
class DocImage extends StatefulWidget {
  const DocImage({
    required this.repo,
    required this.projectId,
    required this.sourceId,
    required this.docPath,
    required this.src,
    required this.alt,
    super.key,
  });

  final DocsRepository repo;
  final String projectId;
  final String sourceId;

  /// Jail-relative path of the document holding the reference, so a relative
  /// `src` resolves against the right directory.
  final String docPath;
  final String src;
  final String alt;

  @override
  State<DocImage> createState() => _DocImageState();
}

class _DocImageState extends State<DocImage> {
  Uint8List? _bytes;
  bool _failed = false;
  String? _resolved;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(DocImage old) {
    super.didUpdateWidget(old);
    if (old.src != widget.src || old.docPath != widget.docPath) {
      _bytes = null;
      _failed = false;
      _start();
    }
  }

  void _start() {
    // An absolute URL is somebody else's image; leave it to the network.
    final uri = Uri.tryParse(widget.src);
    if (uri != null && uri.hasScheme) {
      setState(() => _resolved = null);
      return;
    }
    final target = resolveDocLink(
      from: widget.docPath,
      href: widget.src,
      webUrl: '',
      branch: '',
      docPath: '',
    );
    if (target is! DocInternalLink) {
      setState(() => _failed = true);
      return;
    }
    _resolved = target.path;
    unawaited(_fetch(target.path));
  }

  Future<void> _fetch(String path) async {
    final res = await widget.repo.blob(
      widget.projectId,
      widget.sourceId,
      path,
    );
    if (!mounted) return;
    setState(() {
      _bytes = res.valueOrNull;
      _failed = _bytes == null;
    });
  }

  bool get _isSvg => (_resolved ?? widget.src).toLowerCase().endsWith('.svg');

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(widget.src);
    if (uri != null && uri.hasScheme) {
      return _framed(
        Image.network(
          widget.src,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => _placeholder(Icons.broken_image_outlined),
        ),
      );
    }
    if (_failed) return _placeholder(Icons.broken_image_outlined);
    final bytes = _bytes;
    if (bytes == null) return _placeholder(Icons.image_outlined, label: '');
    if (bytes.isEmpty) return _placeholder(Icons.broken_image_outlined);

    // SVG is sanitized server-side before it reaches us; rendering it still
    // needs a vector rasteriser rather than the bitmap decoder.
    if (_isSvg) {
      return _framed(
        SvgPicture.memory(
          bytes,
          fit: BoxFit.contain,
          semanticsLabel: widget.alt.isEmpty ? null : widget.alt,
          placeholderBuilder: (_) => _placeholder(Icons.image_outlined),
        ),
      );
    }
    return _framed(
      Image.memory(
        bytes,
        fit: BoxFit.contain,
        semanticLabel: widget.alt.isEmpty ? null : widget.alt,
        errorBuilder: (_, _, _) => _placeholder(Icons.broken_image_outlined),
      ),
    );
  }

  Widget _framed(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 420, maxWidth: 720),
      child: ClipRRect(borderRadius: BorderRadius.circular(8), child: child),
    ),
  );

  Widget _placeholder(IconData icon, {String? label}) =>
      MarkdownImagePlaceholder(
        icon: icon,
        label: label ?? (widget.alt.isEmpty ? widget.src : widget.alt),
      );
}
