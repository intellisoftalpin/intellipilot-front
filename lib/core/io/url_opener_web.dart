import 'package:web/web.dart' as web;

void openExternalUrl(String url) {
  web.window.open(url, '_blank');
}
