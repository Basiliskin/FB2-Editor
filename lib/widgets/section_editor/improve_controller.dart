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
  truncated,
  nothing,
  tooLarge
}

/// Where one Chunk of a translation stands.
enum PartStatus { running, ready, failed, waiting, handled }

/// One Chunk of a translation run: its paragraphs and its state.
typedef TranslationPart = ({int number, PartStatus status, List<int> paragraphs});

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

  /// Entity names to keep spelled the same way while translating.
  final List<String> Function() names;

  /// Called when a translated Section has been fully accepted: the target
  /// language code, so the editor can offer to change the book's language.
  final void Function(String code)? onTranslated;

  ImproveController(
      {required this.store,
      required this.section,
      required this.bookId,
      required this.bookInfo,
      required this.flush,
      required this.afterApply,
      this.names = _noNames,
      this.onTranslated,
      http.Client Function()? httpFactory})
      : _httpFactory = httpFactory ?? http.Client.new;

  static List<String> _noNames() => const [];

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
  final List<({List<String> p, String title})> _undo = [];
  http.Client? _client;
  int _run = 0;

  /// The translated title, waiting to be accepted (a translation run only).
  String? titleSuggestion;

  // What a stopped run still has to do, so [resume] can carry on after a failure.
  _Run? _stopped;

  // The translation run on screen, for the per-part view.
  _Run? _current;

  /// The Chunks of the translation on screen, in order. Empty for other runs.
  List<TranslationPart> get parts {
    final run = _current;
    if (run == null || run.translateCode == null) return const [];
    return [
      for (var i = 0; i < run.groups.length; i++)
        (
          number: i + 1,
          paragraphs: [for (final k in run.groups[i]) run.indexes[k]],
          status: i < run.done
              ? (run.groups[i].any((k) => suggestions.containsKey(run.indexes[k]))
                  ? PartStatus.ready
                  : PartStatus.handled)
              : i == run.done
                  ? (busy
                      ? PartStatus.running
                      : _stopped != null
                          ? PartStatus.failed
                          : PartStatus.waiting)
                  : PartStatus.waiting
        )
    ];
  }

  bool get translating => parts.isNotEmpty;

  /// Accepts every pending Suggestion of one part.
  void acceptPart(int number) {
    final part = parts.firstWhere((p) => p.number == number);
    accept(part.paragraphs);
  }

  void rejectPart(int number) {
    final part = parts.firstWhere((p) => p.number == number);
    suggestions = Map.of(suggestions)..removeWhere((k, _) => part.paragraphs.contains(k));
    _finishTranslation();
    notifyListeners();
  }

  bool get canUndo => _undo.isNotEmpty;

  /// A failed or cancelled run can carry on from the Chunk where it stopped.
  bool get canResume => _stopped != null && !busy;

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
    _stopped = null;
    _current = null;
    titleSuggestion = null;
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
    titleSuggestion = null;
    _stopped = null;
    _current = null;
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
    titleSuggestion = null;
    _stopped = null;
    _current = null;
    error = null;
    start = 0;
    end = section.p.isEmpty ? 0 : section.p.length - 1;
    notifyListeners();
  }

  Future<void> ask(String instruction, ConfirmSend confirm,
      {String? translateTo, String? translateCode}) async {
    final provider = current;
    if (provider == null || busy) return;
    flush();
    final indexes = eligible;
    final texts = [for (final i in indexes) section.editableText(section.p[i])];
    if (texts.isEmpty) return _fail(ImproveError.nothing);
    // The title travels in the first Chunk when the range starts the Section.
    final withTitle = translateTo != null &&
        section.title.trim().isNotEmpty &&
        indexes.first == [for (var i = 0; i < section.p.length; i++) if (section.isTextParagraph(i)) i].first;
    final List<List<int>> groups;
    try {
      groups = ImprovementService.chunk(texts, provider.chunkChars);
    } on ImprovementException {
      return _fail(ImproveError.tooLarge);
    }
    // several requests cost more, so that is confirmed every time; a translation
    // is a deliberate whole-Section job, so it asks only above 3 requests
    if (!store.isConsented(provider.id) ||
        groups.length > (translateTo != null ? 3 : 1)) {
      if (!await confirm(provider, texts.length,
          ImprovementService.estimateTokens(texts), groups.length)) {
        return;
      }
      await store.consent(provider.id);
    }
    _stopped = null;
    _lastTranslation = null;
    suggestions = {};
    titleSuggestion = null;
    await _go(_current = _Run(
        provider: provider,
        instruction: instruction,
        indexes: indexes,
        texts: texts,
        groups: groups,
        translateCode: translateCode,
        title: withTitle ? section.title.trim() : null));
  }

  /// Translates the chosen paragraphs (and the title, when the range starts the
  /// Section) into [language]. [code] is the language's FB2 code.
  Future<void> translate(String language, String code, ConfirmSend confirm) =>
      ask(translateInstruction(language), confirm,
          translateTo: language, translateCode: code);

  /// Carries on a run that stopped, from the Chunk that did not finish.
  Future<void> resume() async {
    final run = _stopped;
    if (run == null || busy) return;
    _stopped = null;
    await _go(run);
  }

  Future<void> _go(_Run run) async {
    final provider = run.provider;
    final mine = ++_run;
    busy = true;
    error = null;
    chunks = run.groups.length;
    chunk = run.done;
    notifyListeners();
    final client = _client = _httpFactory();
    var stopped = false;
    try {
      final info = bookInfo();
      final translating = run.translateCode != null;
      final service = ImprovementService(createLlmClient(provider, client));
      while (run.done < run.groups.length) {
        final group = run.groups[run.done];
        chunk = run.done + 1;
        notifyListeners();
        final part = [for (final k in group) run.texts[k]];
        final first = run.done == 0 && run.title != null;
        final context = ImprovementContext(
            bookTitle: info.title,
            language: info.lang,
            genre: info.genre,
            styleNote: styleNote,
            names: translating ? names() : const [],
            previous: translating
                ? ImprovementService.tail(run.sentTexts, run.results)
                : const []);
        final result = await service.improve(
            first ? [run.title!, ...part] : part, run.instruction, context,
            limit: provider.chunkChars);
        if (mine != _run) return;
        final body = first ? result.sublist(1) : result;
        if (first) titleSuggestion = result.first;
        run.sentTexts.addAll(part);
        run.results.addAll(body);
        run.done++;
        // Suggestions show up as each part arrives, and survive a later failure.
        suggestions = {
          ...suggestions,
          for (var k = 0; k < group.length; k++)
            if (body[k] != part[k]) run.indexes[group[k]]: body[k]
        };
        notifyListeners();
      }
      if (suggestions.isEmpty && titleSuggestion == null) {
        error = ImproveError.nothing;
      }
      _lastTranslation = run.translateCode;
    } on LlmException catch (e) {
      if (mine != _run) return;
      stopped = true;
      error = switch (e.failure) {
        LlmFailure.invalidKey => ImproveError.invalidKey,
        LlmFailure.rateLimited => ImproveError.rateLimited,
        LlmFailure.network => ImproveError.network,
        LlmFailure.badResponse => ImproveError.badResponse,
      };
      errorDetail = e.message;
    } on ImprovementException catch (e) {
      if (mine != _run) return;
      stopped = true;
      error = e.truncated ? ImproveError.truncated : ImproveError.rejected;
      errorDetail = e.message;
    } finally {
      client.close();
      if (mine == _run) {
        // a run with Chunks left can be resumed from the one that failed
        if (stopped && run.done < run.groups.length) _stopped = run;
        busy = false;
        chunks = chunk = 0;
        notifyListeners();
      }
    }
  }

  String? _lastTranslation;

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
    chunks = chunk = 0;
    // parts that never ran are gone; what arrived stays to be reviewed
    final run = _current;
    if (run != null && run.done < run.groups.length) {
      run.groups.removeRange(run.done, run.groups.length);
    }
    notifyListeners();
  }

  void reject(int i) {
    suggestions = Map.of(suggestions)..remove(i);
    _finishTranslation();
    notifyListeners();
  }

  void rejectTitle() {
    titleSuggestion = null;
    notifyListeners();
  }

  void acceptTitle() {
    final t = titleSuggestion;
    if (t == null) return;
    _undo.add((p: List.of(section.p), title: section.title));
    section.title = t;
    titleSuggestion = null;
    afterApply();
    _finishTranslation();
    notifyListeners();
  }

  void accept(Iterable<int> indexes) {
    final chosen = {
      for (final i in indexes)
        if (suggestions.containsKey(i)) i: suggestions[i]!
    };
    if (chosen.isEmpty) return;
    _undo.add((p: List.of(section.p), title: section.title));
    section.applyTexts(chosen);
    suggestions = Map.of(suggestions)..removeWhere((k, _) => chosen.containsKey(k));
    afterApply();
    _finishTranslation();
    notifyListeners();
  }

  /// Tells the editor once a translation has been dealt with in full.
  void _finishTranslation() {
    final code = _lastTranslation;
    if (code == null ||
        suggestions.isNotEmpty ||
        titleSuggestion != null ||
        _stopped != null ||
        busy ||
        _undo.isEmpty) {
      return;
    }
    _lastTranslation = null;
    onTranslated?.call(code);
  }

  /// Puts back the paragraphs as they were before the last accept.
  void undo() {
    if (_undo.isEmpty) return;
    final before = _undo.removeLast();
    section.p = before.p;
    section.title = before.title;
    suggestions = {};
    titleSuggestion = null;
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

/// A run of Chunks, kept so it can carry on after a failure.
class _Run {
  final Provider provider;
  final String instruction;
  final List<int> indexes;
  final List<String> texts;
  final List<List<int>> groups;
  final String? translateCode;
  final String? title;

  /// Chunks finished so far, and the texts they covered with their results.
  int done = 0;
  final sentTexts = <String>[];
  final results = <String>[];
  _Run(
      {required this.provider,
      required this.instruction,
      required this.indexes,
      required this.texts,
      required this.groups,
      this.translateCode,
      this.title});
}
