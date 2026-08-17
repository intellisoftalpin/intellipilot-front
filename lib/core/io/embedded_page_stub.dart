import 'package:flutter/widgets.dart';

/// Non-web targets have no frame to put a foreign page in.
const bool isSupported = false;

/// Never rendered: callers check [isSupported] and show the open-in-a-browser
/// affordance instead.
Widget buildEmbeddedPage(String url) => const SizedBox.shrink();
