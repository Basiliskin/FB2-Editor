import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:quill_fb2/models/section.model.dart';
import 'package:quill_fb2/services/llm/adapters.dart';
import 'package:quill_fb2/services/llm/improvement.dart';
import 'package:quill_fb2/services/llm/llm_client.dart';
import 'package:quill_fb2/services/llm/provider_store.dart';

enum ImproveError {
  invalidKey,
  rateLimited,
  network,
  badResponse,
  rejected,
  nothing,
  tooLarge
}

typedef BookInfo = ({String title, String lang, String genre});
typedef ConfirmSend = Future<bool> Function(
    Provider provider, int paragraphs, int tokens, int requests);

/// State of the Improve command bar: which paragraphs are chosen, the pending
/// Suggestions, and the request in flight.
class ImproveController extends ChangeNotifier {
  final ProviderStore store;
  final Section section;
  final String bookId;
  final BookInfo Function() bookInfo;

  /// Commits the paragraph being typed into the section.
  final VoidCallback flush;

  /// Lets the editor drop cached text after the section changed.
  final VoidCallback afterApply;
  final http.Client Function() _httpFactory;

  ImproveController(
      {required this.store,
      required this.section,
      required this.bookId,
      required this.bookInfo,
      required this.flush,
      required this.afterApply,
      http.Client Function()? httpFactory})
      : _httpFactory = httpFactory ?? http.Client.new;

  bool open = false, busy = false;

  /// Which request of how many is running (0 when idle).
  int chunk = 0, chunks = 0;
  ImproveError? error;
  String errorDetail = '';
  int start = 0, end = 0;
  Map<int, String> suggestions = {};
  List<Provider> providers = [];
  List<Preset> presets = defaultPresets;
  Provider? current;
  List<String>? _undo;
  http.Client? _client;
  int _run = 0;

  bool get canUndo => _undo != null;

  bool inRange(int i) => open && i >= start && i <= end;

  List<int> get eligible => [
        for (var i = start; i <= end && i < section.p.length; i++)
          if (section.isTextParagraph(i)) i
      ];

  int get tokenEstimate => ImprovementService.estimateTokens(
      [for (final i in eligible) section.editableText(section.p[i])]);

  String get styleNote => store.styleNote(bookId);
  Future<void> setStyleNote(String note) async {
    await store.setStyleNote(bookId, note);
    notifyListeners();
  }

  Future<void> toggle(int active) async {
    if (open) return close();
    flush();
    final last = section.p.isEmpty ? 0 : section.p.length - 1;
    start = end = active.clamp(0, last);
    open = true;
    error = null;
    suggestions = {};
    notifyListeners();
    await reload();
  }

  void close() {
    cancel();
    open = false;
    suggestions = {};
    error = null;
    notifyListeners();
  }

  Future<void> reload() async {
    final all = await store.list();
    providers = all;
    presets = [...defaultPresets, ...store.customPresets()];
    current = all.isEmpty
        ? null
        : all.firstWhere((p) => p.id == current?.id,
            orElse: () => all.firstWhere((p) => p.id == store.defaultId,
                orElse: () => all.first));
    notifyListeners();
  }

  Future<void> savePreset(Preset p) async {
    await store.savePreset(p);
    await reload();
  }

  Future<void> deletePreset(String id) async {
    await store.deletePreset(id);
    await reload();
  }

  void selectProvider(Provider p) {
    current = p;
    notifyListeners();
  }

  /// Tapping a paragraph widens the range to it, or narrows it from an end.
  void tapParagraph(int i) {
    suggestions = {};
    error = null;
    if (i < start) {
      start = i;
    } else if (i > end) {
      end = i;
    } else if (start != end) {
      i == start ? start++ : end--;
    }
    notifyListeners();
  }

  void selectAll() {
    suggestions = {};
    error = null;
    start = 0;
    end = section.p.isEmpty ? 0 : section.p.length - 1;
    notifyListeners();
  }

  Future<void> ask(String instruction, ConfirmSend confirm) async {
    final provider = current;
    if (provider == null || busy) return;
    flush();
    final indexes = eligible;
    final texts = [for (final i in indexes) section.editableText(section.p[i])];
    if (texts.isEmpty) return _fail(ImproveError.nothing);
    final List<List<int>> groups;
    try {
      groups = ImprovementService.chunk(texts);
    } on ImprovementException {
      return _fail(ImproveError.tooLarge);
    }
    // several requests cost more, so that is confirmed every time
    if (!store.isConsented(provider.id) || groups.length > 1) {
      if (!await confirm(provider, texts.length,
          ImprovementService.estimateTokens(texts), groups.length)) {
        return;
      }
      await store.consent(provider.id);
    }
    final mine = ++_run;
    busy = true;
    error = null;
    suggestions = {};
    chunks = groups.length;
    chunk = 0;
    notifyListeners();
    final client = _client = _httpFactory();
    try {
      final info = bookInfo();
      final context = ImprovementContext(
          bookTitle: info.title,
          language: info.lang,
          genre: info.genre,
          styleNote: styleNote);
      final service = ImprovementService(createLlmClient(provider, client));
      for (final group in groups) {
        chunk++;
        notifyListeners();
        final part = [for (final k in group) texts[k]];
        final result = await service.improve(part, instruction, context);
        if (mine != _run) return;
        // Suggestions show up as each part arrives, and survive a later failure.
        suggestions = {
          ...suggestions,
          for (var k = 0; k < group.length; k++)
            if (result[k] != part[k]) indexes[group[k]]: result[k]
        };
        notifyListeners();
      }
      if (suggestions.isEmpty) error = ImproveError.nothing;
    } on LlmException catch (e) {
      if (mine != _run) return;
      error = switch (e.failure) {
        LlmFailure.invalidKey => ImproveError.invalidKey,
        LlmFailure.rateLimited => ImproveError.rateLimited,
        LlmFailure.network => ImproveError.network,
        LlmFailure.badResponse => ImproveError.badResponse,
      };
      errorDetail = e.message;
    } on ImprovementException catch (e) {
      if (mine != _run) return;
      error = ImproveError.rejected;
      errorDetail = e.message;
    } finally {
      client.close();
      if (mine == _run) {
        busy = false;
        chunks = chunk = 0;
        notifyListeners();
      }
    }
  }

  void _fail(ImproveError e) {
    error = e;
    notifyListeners();
  }

  /// Abandons the request in flight; its answer is ignored.
  void cancel() {
    if (!busy) return;
    _run++;
    _client?.close();
    busy = false;
    notifyListeners();
  }

  void reject(int i) {
    suggestions = Map.of(suggestions)..remove(i);
    notifyListeners();
  }

  void accept(Iterable<int> indexes) {
    final chosen = {
      for (final i in indexes)
        if (suggestions.containsKey(i)) i: suggestions[i]!
    };
    if (chosen.isEmpty) return;
    _undo = List.of(section.p);
    section.applyTexts(chosen);
    suggestions = Map.of(suggestions)..removeWhere((k, _) => chosen.containsKey(k));
    afterApply();
    notifyListeners();
  }

  /// Puts back the paragraphs as they were before the last accept.
  void undo() {
    final before = _undo;
    if (before == null) return;
    section.p = before;
    _undo = null;
    suggestions = {};
    afterApply();
    notifyListeners();
  }

  @override
  void dispose() {
    _run++;
    _client?.close();
    super.dispose();
  }
}
