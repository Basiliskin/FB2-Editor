import 'package:flutter/material.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/ui/widgets.dart';

/// One help topic: a heading with a few short tips, each an (en, ru) pair.
class HelpTopic {
  final IconData icon;
  final (String, String) title;
  final List<(String, String)> tips;

  /// Lets a screen open the help on this topic; empty when no screen links to it.
  final String id;
  const HelpTopic(this.icon, this.title, this.tips, {this.id = ''});
}

const helpTopics = <HelpTopic>[
  HelpTopic(Icons.local_library_outlined, ('Library', 'Библиотека'), [
    (
      'Tap "Load book" to pick an .fb2 or .epub file, a .zip archive that contains an .fb2, or a plain .txt file (it becomes a book; lines like "Chapter 2" or "Глава 2" start new sections). "New book" starts an empty one.',
      'Нажмите «Загрузить книгу», чтобы выбрать файл .fb2 или .epub, архив .zip с книгой .fb2 или обычный .txt (он станет книгой; строки вида «Глава 2» или "Chapter 2" начинают новые разделы). «Новая книга» создаёт пустую.'
    ),
    (
      'Books you opened appear as covers, newest first. Tap a cover to continue editing.',
      'Открытые книги отображаются обложками, новые первыми. Нажмите на обложку, чтобы продолжить редактирование.'
    ),
    (
      'Use the search field to filter by title or author.',
      'Поле поиска фильтрует книги по названию или автору.'
    ),
    (
      'The ⋮ menu on a cover removes the book from the list. The book file itself is not deleted.',
      'Меню ⋮ на обложке убирает книгу из списка. Сам файл книги не удаляется.'
    ),
  ]),
  HelpTopic(Icons.info_outline, ('Book info', 'О книге'), [
    (
      'The "Info" tab edits the title, author (name, home page), genre, series and annotation.',
      'Вкладка «Инфо» редактирует название, автора (имя, сайт), жанр, серию и аннотацию.'
    ),
    (
      'Tap the cover to choose a cover image from your device.',
      'Нажмите на обложку, чтобы выбрать изображение с устройства.'
    ),
    (
      'Genres and series are labels: type a name and press Enter to add it, tap a label\'s ✕ to remove it.',
      'Жанры и серии — это метки: введите название и нажмите Enter, чтобы добавить; ✕ на метке удаляет её.'
    ),
  ]),
  HelpTopic(Icons.list_alt_outlined, ('Sections', 'Разделы'), [
    (
      'The "Sections" tab lists the chapters of the book. Tap "New section" to add one.',
      'Вкладка «Разделы» показывает главы книги. «Новый раздел» добавляет главу.'
    ),
    (
      'Edit a title in place and press Enter to apply it.',
      'Название можно править прямо в списке; подтвердите клавишей Enter.'
    ),
    (
      'Drag the ⠿ handle to reorder sections.',
      'Перетащите значок ⠿, чтобы изменить порядок разделов.'
    ),
    (
      'Tap a section\'s number to select it. Select several, then tap "Delete" to remove them together. Swiping a section away also removes it.',
      'Нажмите на номер раздела, чтобы выбрать его. Выберите несколько и нажмите «Удалить», чтобы удалить их разом. Смахивание раздела тоже удаляет его.'
    ),
    (
      'The pencil button opens the section in the text editor.',
      'Кнопка с карандашом открывает раздел в текстовом редакторе.'
    ),
  ]),
  HelpTopic(Icons.edit_note_outlined, ('Text editor', 'Текстовый редактор'), [
    (
      'Undo and redo are the first two toolbar buttons.',
      'Отмена и повтор — первые две кнопки панели.'
    ),
    (
      'Select text, then tap Bold, Italic or Quote. They are saved as FB2 <strong>, <emphasis> and <cite> tags. Quote asks for an optional author.',
      'Выделите текст и нажмите «Жирный», «Курсив» или «Цитата». В FB2 они сохраняются как теги <strong>, <emphasis> и <cite>. Для цитаты можно указать автора.'
    ),
    (
      'Book button: creates a new section from the text in your clipboard and asks you for its name.',
      'Кнопка с книгой: создаёт новый раздел из текста в буфере обмена и спрашивает его название.'
    ),
    (
      'Contact-page button: adds the clipboard text to the book annotation.',
      'Кнопка с карточкой: добавляет текст из буфера обмена в аннотацию книги.'
    ),
    (
      'Image button: choose a picture and it is inserted after the paragraph you are editing (or at the end). Use as many as you like; the bin icon on a picture removes it.',
      'Кнопка с картинкой: выберите изображение, и оно вставится после редактируемого абзаца (или в конец). Картинок может быть сколько угодно; значок корзины на картинке удаляет её.'
    ),
    (
      'Poem button: copy the verses first (a blank line starts a new stanza), then tap it. The poem is inserted after the paragraph you are editing; tap it to change the lines.',
      'Кнопка стихов: сначала скопируйте стихи (пустая строка начинает новую строфу), затем нажмите её. Стихотворение вставится после редактируемого абзаца; нажмите на него, чтобы изменить строки.'
    ),
  ]),
  HelpTopic(
      Icons.hub_outlined,
      ('Story map', 'Карта истории'),
      id: 'story-map',
      [
    (
      'Open it with the Story map button (three linked dots) on the book screen; on a narrow screen it is in the ⋮ menu. The map is built automatically from your text: names that keep their capital letter inside a sentence become people, and it counts who appears in which section. Nothing leaves your device.',
      'Откройте её кнопкой «Карта истории» (три связанные точки) на экране книги; на узком экране она в меню ⋮. Карта строится сама по вашему тексту: слова, которые остаются с заглавной буквы внутри предложения, становятся героями, и считается, кто в каких разделах встречается. Ничего не покидает ваше устройство.'
    ),
    (
      'Reading it: sections run down the side in book order; people, places, events and lore run across the top, in groups. A coloured cell means that item appears in that section, a darker one means more mentions. The book is split into three acts; tap an act\'s name to fold it.',
      'Как читать: разделы идут сверху вниз в порядке книги, а герои, места, события и мир — слева направо группами. Цветная ячейка — объект встречается в разделе, чем темнее, тем чаще. Книга делится на три акта; нажмите название акта, чтобы свернуть его.'
    ),
    (
      'Colours: people are blue (protagonist), green (major) or purple (minor). Places, events and lore have their own icons and colours.',
      'Цвета: герои бывают синими (главный), зелёными (важные) и фиолетовыми (второстепенные). У мест, событий и мира свои значки и цвета.'
    ),
    (
      'Tap a section to see who and what is in it. Tap a column title to toggle it; toggle several, then "Apply" keeps only those columns and "Reset" brings them all back. The filter button lists every item with checkboxes. The search box narrows the columns and the sort button orders them.',
      'Нажмите на раздел, чтобы увидеть, кто и что в нём есть. Нажмите заголовок колонки, чтобы отметить её; отметьте несколько, и «Применить» оставит только их, а «Сбросить» вернёт все. Кнопка фильтра показывает все объекты с галочками. Поле поиска сужает колонки, кнопка сортировки задаёт их порядок.'
    ),
    (
      'Zoom buttons switch between roomy, compact and "fit to width" (every column on screen). The map button shows an overview of the whole book: tap or drag it to jump. Tap a group header (People, Places…) to widen just that group and read its names.',
      'Кнопки масштаба переключают крупный, компактный и «по ширине» (все колонки на экране) вид. Кнопка с картой показывает обзор всей книги: нажмите или проведите по ней, чтобы перейти. Нажмите заголовок группы (Герои, Места…), чтобы расширить только её и прочитать имена.'
    ),
    (
      'Add, change, remove: tap the pencil, then "+" to add a person, place, event or piece of lore (name, kind, role, note). Tap a column title to rename it, change its kind, role or note, connect it to others, or remove it. "Undo" in the message brings a removed item back.',
      'Добавить, изменить, убрать: нажмите карандаш, затем «+», чтобы добавить героя, место, событие или элемент мира (название, вид, роль, заметка). Нажмите заголовок колонки, чтобы переименовать её, сменить вид, роль или заметку, связать с другими или убрать. «Отменить» в сообщении вернёт убранное.'
    ),
    (
      'Check names (⋮ menu): finds names the book writes in more than one way, such as Ivan and Иван, Фёдор and Федор, or a rare slip like Артор next to Артур. It runs on your device and shows where each spelling stands. For unclear pairs you can tap "Ask AI": only short quotes around those names go to your AI provider, after you confirm. Nothing in the book is changed; "Dismiss" hides a finding for good.',
      'Проверить имена (меню ⋮): находит имена, которые в книге написаны по-разному, например Ivan и Иван, Фёдор и Федор или редкая опечатка вроде Артор рядом с Артур. Проверка идёт на вашем устройстве и показывает, где стоит каждое написание. Для неясных пар можно нажать «Спросить ИИ»: вашему ИИ-провайдеру уходят только короткие цитаты вокруг этих имён, после вашего подтверждения. Книга не меняется; «Скрыть» убирает находку насовсем.'
    ),
    (
      'While editing, tap a cell to mark or unmark where something appears. A mark you make by hand counts as one mention.',
      'В режиме правки нажмите ячейку, чтобы отметить или снять отметку, где что встречается. Ручная отметка считается одним упоминанием.'
    ),
    (
      'Connections: in an item\'s editor, "Add" connects it to another item with a short label such as "brother of", "lives in" or "caused by". Tap a connection to change its label, or the broken-link icon to remove it. Items that share paragraphs are connected automatically.',
      'Связи: в окне правки объекта «Добавить» связывает его с другим объектом короткой подписью, например «брат», «живёт в» или «вызвано». Нажмите связь, чтобы изменить подпись, или значок разорванной цепи, чтобы убрать её. Объекты, которые встречаются в одних абзацах, связываются сами.'
    ),
    (
      'In the section editor, the same button shows the same map for just that section, so you can add or remove who is in it while you write. Section cards in the Sections tab show who is in them.',
      'В редакторе раздела та же кнопка показывает карту только этого раздела, чтобы вы могли добавлять и убирать героев, пока пишете. Карточки на вкладке «Разделы» показывают, кто в них есть.'
    ),
    (
      'The flag button lists people to check, for example someone important who disappears for a whole act.',
      'Кнопка с флажком показывает, что стоит проверить, например важного героя, который пропадает на целый акт.'
    ),
    (
      'Saving: the map is kept inside the book, in the FB2 file\'s description where other readers ignore it, and is written when you save or export the book. EPUB and TXT files do not include it. "Rebuild from the text" in the ⋮ menu throws away your edits and builds a fresh map.',
      'Сохранение: карта хранится внутри книги, в описании файла FB2, где другие программы её игнорируют, и записывается, когда вы сохраняете или экспортируете книгу. В файлы EPUB и TXT она не попадает. «Пересобрать по тексту» в меню ⋮ отбрасывает ваши правки и строит новую карту.'
    ),
    (
      'Good to know: names are found by their capital letters, so someone always called by a title or a nickname may be missed, and two people who share a surname can get mixed up. Fix these by hand.',
      'Полезно знать: имена находятся по заглавным буквам, поэтому героя, которого всегда называют по титулу или прозвищу, можно пропустить, а двух героев с общей фамилией — перепутать. Исправьте это вручную.'
    ),
  ]),
  HelpTopic(Icons.save_outlined, ('Saving & export', 'Сохранение и экспорт'), [
    (
      '"Save & export" (top right of the book screen) opens one menu: "Save in the app" keeps the book in the app\'s private workspace, and the other entries export a file. It also shows whether you have unsaved changes.',
      '«Сохранить и экспорт» (справа вверху на экране книги) открывает одно меню: «Сохранить в приложении» хранит книгу в закрытом рабочем пространстве приложения, остальные пункты создают файл. Там же видно, есть ли несохранённые изменения.'
    ),
    (
      'Auto-save (✨ in the book screen, or in Settings) also saves when you leave the editor or put the app in the background. Green means on.',
      'Автосохранение (✨ на экране книги или в настройках) также сохраняет при выходе из редактора и сворачивании приложения. Зелёный значок — включено.'
    ),
    (
      'Find and replace (magnifier with arrows on the book screen) works on the whole book: text only, never links or pictures. "Add another book" appends the chapters of an .fb2, .epub, .zip or .txt file after yours, with its pictures and footnotes; your cover and details stay.',
      'Поиск и замена (лупа со стрелками на экране книги) работают по всей книге: только текст, ссылки и картинки не затрагиваются. «Добавить другую книгу» дописывает главы из файла .fb2, .epub, .zip или .txt после ваших вместе с картинками и сносками; ваша обложка и данные остаются.'
    ),
    (
      'Translate (✨ in the section editor, then "Translate..."): pick a language and, if you like, "Whole Section". Text goes in several requests, each one seeing the end of the previous translation, and the names on your story map are kept spelled the same way (transliterated, not translated). The section title is translated too. Each part of the text gets a header; its original and translation are shown side by side. Accept or reject a part, or tap "Retry" on a failed one to carry on. The chips in the bar show where every part stands. Formatting tags are checked, and "Undo" steps back one accept at a time. When most of the book is translated, you are asked whether to change the book language.',
      'Перевод (✨ в редакторе раздела, затем «Перевести...»): выберите язык и, при желании, «Весь раздел». Текст уходит несколькими запросами, и каждый видит конец предыдущего перевода; имена с карты сюжета пишутся одинаково (транслитерация, не перевод смысла). Заголовок раздела тоже переводится. У каждой части есть заголовок, оригинал и перевод показаны рядом. Принимайте или отклоняйте часть целиком, а у неудавшейся нажмите «Повторить». Значки в панели показывают состояние каждой части. Теги форматирования проверяются, а «Отменить» возвращает по одному принятию. Когда переведена большая часть книги, приложение спросит, сменить ли язык книги.'
    ),
    (
      'Ask about the book (⋮ menu on the book screen): pick a range of sections, then "Summarise" or ask a question. It needs an AI provider, shows the size and number of requests first, and never changes your book. A short range goes to the model as text; a long one is first reduced to short summaries of each section (kept, so asking again is cheaper), and the answer then says it is less detailed. Quotes the model gives as evidence are checked against your text and marked when they are not found.',
      'Вопрос о книге (меню ⋮ на экране книги): выберите диапазон разделов, затем «Пересказ» или задайте вопрос. Нужен ИИ-провайдер; сначала показывается размер и число запросов, а книга не меняется. Короткий диапазон уходит модели текстом; длинный сначала сжимается в краткие пересказы разделов (они сохраняются, поэтому повторный вопрос дешевле), и ответ отмечает, что он менее подробный. Цитаты-подтверждения проверяются по вашему тексту и помечаются, если не найдены.'
    ),
    (
      'Export writes a ready file where you choose (in the browser it downloads the file): FB2 is the editable book, EPUB is for e-readers, TXT is plain text. The file is named "Author - Title" with its extension and always contains your latest edits.',
      'Экспорт создаёт готовый файл в выбранном месте (в браузере файл скачивается): FB2 — редактируемая книга, EPUB — для читалок, TXT — простой текст. Файл называется «Автор - Название» с нужным расширением и всегда содержит последние правки.'
    ),
    (
      'Your original file is never changed. Your reader may keep showing the old copy: remove the old book from the reader and add the exported file.',
      'Исходный файл не изменяется. Читалка может показывать старую копию: удалите старую книгу в читалке и добавьте экспортированный файл.'
    ),
    (
      'Leaving a screen with unsaved changes asks whether to save them.',
      'При выходе с несохранёнными изменениями приложение спросит, сохранить ли их.'
    ),
  ]),
  HelpTopic(Icons.settings_outlined, ('Settings', 'Настройки'), [
    (
      'Editing: auto-save and the editor font size.',
      'Редактирование: автосохранение и размер шрифта.'
    ),
    (
      'Images: maximum width and JPEG quality for pictures you add. Smaller values give smaller books; quality 100 keeps the original file untouched.',
      'Изображения: максимальная ширина и качество JPEG добавляемых картинок. Меньшие значения дают меньший размер книги; качество 100 сохраняет исходный файл без изменений.'
    ),
    (
      'Language: switch between English and Russian.',
      'Язык: переключение между английским и русским.'
    ),
    (
      'Tap "Save" to apply the changes.',
      'Нажмите «Сохранить», чтобы применить изменения.'
    ),
  ]),
  HelpTopic(Icons.lightbulb_outline, ('Good to know', 'Полезно знать'), [
    (
      'Slightly damaged FB2 files usually still open: the parser skips broken parts and retries.',
      'Слегка повреждённые файлы FB2 обычно открываются: парсер пропускает битые части и пробует снова.'
    ),
    (
      'Old books in Windows-1251 encoding are recognised automatically.',
      'Старые книги в кодировке Windows-1251 распознаются автоматически.'
    ),
    (
      'Everything stays on your device. There is no account and no server.',
      'Всё хранится на вашем устройстве. Нет ни аккаунта, ни сервера.'
    ),
  ]),
];

/// Pushes the help screen. Shared by every screen that has a help button.
Future<void> openHelp(BuildContext context, AppService service, {String? topic}) =>
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => HelpScreen(service, topic: topic)));

class HelpScreen extends StatelessWidget {
  final AppService service;

  /// The id of a [HelpTopic] to show first and open.
  final String? topic;
  const HelpScreen(this.service, {this.topic, super.key});

  /// The requested topic first, so it is in view when it opens.
  List<HelpTopic> get _ordered => [
        ...helpTopics.where((x) => topic != null && x.id == topic),
        ...helpTopics.where((x) => topic == null || x.id != topic),
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: appBarFor(context, title: Text(tr(service, 'Help', 'Справка'))),
      body: PageBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            for (final t in _ordered)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  initiallyExpanded: topic != null && t.id == topic,
                  leading: Icon(t.icon, color: theme.colorScheme.primary),
                  title: Text(tr(service, t.title.$1, t.title.$2),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final tip in t.tips)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('•  '),
                              Expanded(
                                  child: Text(tr(service, tip.$1, tip.$2),
                                      style: theme.textTheme.bodyMedium)),
                            ]),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
