import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/ui/widgets.dart';

/// Why a provider could not be reached, with the hint that fits the platform.
///
/// A browser reports a CORS block as an ordinary network failure, so on web the
/// message names it as a likely cause rather than claiming it.
String networkMessage(AppService s, {required bool web, String baseUrl = ''}) {
  final base = tr(s, 'Could not reach the provider', 'Нет связи с провайдером');
  if (web) {
    return base +
        tr(
            s,
            '. A browser may block direct calls to this provider (CORS); the Android app is not affected.',
            '. Браузер может блокировать прямые запросы к этому провайдеру (CORS); в Android-приложении этого нет.');
  }
  if (baseUrl.trim().startsWith('http://')) {
    return base +
        tr(s, '. Android may block plain http, try https.',
            '. Android может блокировать http, нужен https.');
  }
  return base;
}
