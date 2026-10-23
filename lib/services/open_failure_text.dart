import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/services/open_failure.dart';
import 'package:quill_fb2/utils/consts.dart';

/// The localized reason a file could not be opened; anything unexpected reads as "unreadable".
String openFailureMessage(AppService service, Object error) {
  final item = switch (error is OpenFailure ? error.kind : OpenFailureKind.unreadable) {
    OpenFailureKind.unsupportedType => LangTranslateItems.openErrorUnsupported,
    OpenFailureKind.unreadable => LangTranslateItems.openErrorUnreadable,
    OpenFailureKind.noFb2InZip => LangTranslateItems.openErrorNoFb2InZip,
    OpenFailureKind.notFb2 => LangTranslateItems.openErrorNotFb2,
    OpenFailureKind.notEpub => LangTranslateItems.openErrorNotEpub,
    OpenFailureKind.timeout => LangTranslateItems.openErrorTimeout,
  };
  return service.translate(item);
}
