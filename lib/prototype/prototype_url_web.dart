// PROTOTYPE: keeps ?variant= in the browser URL (reload-stable, shareable).
import 'dart:html' as html;

String? readVariantFromUrl() => Uri.base.queryParameters['variant'];

void writeVariantToUrl(String variant) {
  final uri = Uri.base.replace(
      queryParameters: {...Uri.base.queryParameters, 'variant': variant});
  html.window.history.replaceState(null, '', uri.toString());
}
