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

  /// The button a tip is about, by the tip's index, shown in place of its bullet.
  final Map<int, IconData> icons;
  const HelpTopic(this.icon, this.title, this.tips, {this.id = '', this.icons = const {}});
}

const helpTopics = <HelpTopic>[
  HelpTopic(Icons.local_library_outlined, ('Library', 'Библиотека'), icons: {
    0: Icons.add_circle_outline,
    2: Icons.search,
    3: Icons.more_vert,
    4: Icons.settings_outlined,
  }, [
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
      'The ⋮ menu on a cover has "Remove from list". The book file itself is not deleted.',
      'В меню ⋮ на обложке есть «Убрать из списка». Сам файл книги не удаляется.'
    ),
    (
      'Settings (gear) and Help (?) are at the top of the library.',
      'Настройки (шестерёнка) и справка (?) — вверху библиотеки.'
    ),
  ]),
  HelpTopic(Icons.info_outline, ('Book info', 'О книге'), icons: {
    2: Icons.delete_outline,
    3: Icons.hub_outlined,
  }, [
    (
      'The "Info" tab edits the title, the author (first, middle and last name, home page, email), genre, series and annotation, plus "Book details" (language, date, keywords) and "File info" (version, ID).',
      'Вкладка «Инфо» редактирует название, автора (имя, отчество, фамилия, сайт, почта), жанр, серию и аннотацию, а также «Сведения о книге» (язык, дата, ключевые слова) и «О файле» (версия, ID).'
    ),
    (
      'Tap the cover to choose a cover image from your device.',
      'Нажмите на обложку, чтобы выбрать изображение с устройства.'
    ),
    (
      'Remove cover (bin): shown when the book has a cover.',
      'Удалить обложку (корзина): видна, когда у книги есть обложка.'
    ),
    (
      'The button on the cover opens the story map.',
      'Кнопка на обложке открывает карту истории.'
    ),
    (
      'Genres and series are labels: type a name and press Enter to add it, tap a label\'s ✕ to remove it.',
      'Жанры и серии — это метки: введите название и нажмите Enter, чтобы добавить; ✕ на метке удаляет её.'
    ),
  ]),
  HelpTopic(Icons.list_alt_outlined, ('Sections', 'Разделы'), icons: {
    0: Icons.add,
    2: Icons.drag_indicator,
    4: Icons.edit_outlined,
  }, [
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
      'Tap a section\'s number to select it. Select several, then tap "Delete" (it replaces "New section") to remove them together. Swiping a section away asks before deleting it.',
      'Нажмите на номер раздела, чтобы выбрать его. Выберите несколько и нажмите «Удалить», чтобы удалить их разом. Смахивание раздела тоже удаляет его, после подтверждения.'
    ),
    (
      'The pencil button opens the section in the text editor.',
      'Кнопка с карандашом открывает раздел в текстовом редакторе.'
    ),
    (
      'Each card shows how many paragraphs the section has and the people who appear in it.',
      'На каждой карточке видно число абзацев и герои, которые появляются в разделе.'
    ),
  ]),
  HelpTopic(Icons.edit_note_outlined, ('Text editor', 'Текстовый редактор'), icons: {
    1: Icons.undo_outlined,
    2: Icons.format_bold,
    3: Icons.superscript,
    4: Icons.mic_none,
    5: Icons.auto_awesome_outlined,
    6: Icons.translate,
    7: Icons.save_outlined,
    8: Icons.more_vert,
    9: Icons.image,
    10: Icons.lyrics_outlined,
    11: Icons.book,
    12: Icons.contact_page,
  }, [
    (
      'Tap a paragraph to edit it. The buttons below appear in the bar above the text while a paragraph is open; tap "Add paragraph" at the end of the section for a new one.',
      'Нажмите на абзац, чтобы изменить его. Кнопки ниже появляются на панели над текстом, пока абзац открыт; «Добавить абзац» в конце раздела создаёт новый.'
    ),
    (
      'Undo and Redo: the two arrows at the start of the bar.',
      'Отменить и Повторить — две стрелки в начале панели.'
    ),
    (
      'Bold, Italic, Quote: select text, then tap B, I or the quote mark. They are saved as FB2 <strong>, <emphasis> and <cite>. Quote asks for an optional author.',
      'Жирный, Курсив, Цитата: выделите текст и нажмите B, I или кавычки. В FB2 они сохраняются как <strong>, <emphasis> и <cite>. Для цитаты можно указать автора.'
    ),
    (
      'Footnote (x² button): place the cursor where the note goes, tap it, type the label and the note. To change or delete a note, put the cursor on its mark (such as [1]) and tap the button again. A note whose mark you delete is removed when the book is saved.',
      'Сноска (кнопка x²): поставьте курсор туда, где нужна сноска, нажмите её и введите метку и текст. Чтобы изменить или удалить сноску, поставьте курсор на её метку (например, [1]) и снова нажмите кнопку. Сноска, метку которой вы удалили, исчезнет при сохранении книги.'
    ),
    (
      'Microphone: dictate into the paragraph. See "Voice input".',
      'Микрофон: диктовка в абзац. См. «Голосовой ввод».'
    ),
    (
      'Improve with AI (sparkles, top bar): pick the paragraphs, then a preset such as proofread or translate, or type your own instruction. Each suggestion is shown next to the original for you to accept (✓) or reject (✕), and Undo puts the text back. It needs an AI provider (Settings) and asks before sending anything.',
      'Улучшить с ИИ (звёздочки вверху): выберите абзацы, затем шаблон, например «вычитать» или «перевести», или напишите своё указание. Каждое предложение показано рядом с оригиналом — примите (✓) или отклоните (✕); «Отменить» вернёт текст. Нужен ИИ-провайдер (Настройки), и перед отправкой приложение спросит.'
    ),
    (
      'Translate (✨ in the top bar, then "Translate..."): pick a language and, if you like, "Whole Section". Text goes in several requests, each one seeing the end of the previous translation, and the names on your story map are kept spelled the same way (transliterated, not translated). The section title is translated too. Each part of the text gets a header; its original and translation are shown side by side. Accept or reject a part, or tap "Retry" on a failed one to carry on. The chips in the bar show where every part stands. Formatting tags are checked, and "Undo" steps back one accept at a time. When most of the book is translated, you are asked whether to change the book language.',
      'Перевод (✨ на верхней панели, затем «Перевести...»): выберите язык и, при желании, «Весь раздел». Текст уходит несколькими запросами, и каждый видит конец предыдущего перевода; имена с карты сюжета пишутся одинаково (транслитерация, не перевод смысла). Заголовок раздела тоже переводится. У каждой части есть заголовок, оригинал и перевод показаны рядом. Принимайте или отклоняйте часть целиком, а у неудавшейся нажмите «Повторить». Значки в панели показывают состояние каждой части. Теги форматирования проверяются, а «Отменить» возвращает по одному принятию. Когда переведена большая часть книги, приложение спросит, сменить ли язык книги.'
    ),
    (
      'Save (disk, top bar): saves the book in the app.',
      'Сохранить (дискета вверху): сохраняет книгу в приложении.'
    ),
    (
      'The ⋮ menu (top right) holds the rest: Insert picture, Poem, New section and Annotation from copied text, Story map, Export .fb2 and Help.',
      'В меню ⋮ (справа вверху) остальное: картинка, стихи, новая глава и аннотация из скопированного текста, карта истории, экспорт .fb2 и справка.'
    ),
    (
      'Insert picture (⋮ menu): choose a picture and it is inserted after the paragraph you are editing (or at the end). Use as many as you like; the bin icon on a picture removes it.',
      'Вставить картинку (меню ⋮): выберите изображение, и оно вставится после редактируемого абзаца (или в конец). Картинок может быть сколько угодно; значок корзины на картинке удаляет её.'
    ),
    (
      'Poem from copied text (⋮ menu): copy the verses first (a blank line starts a new stanza). The poem is inserted after the paragraph you are editing; tap it to change the lines.',
      'Стихотворение из скопированного текста (меню ⋮): сначала скопируйте стихи (пустая строка начинает новую строфу). Стихотворение вставится после редактируемого абзаца; нажмите на него, чтобы изменить строки.'
    ),
    (
      'New section from copied text (⋮ menu): makes a new section from the clipboard and asks for its name.',
      'Новая глава из скопированного текста (меню ⋮): создаёт раздел из буфера обмена и спрашивает его название.'
    ),
    (
      'Annotation from copied text (⋮ menu): adds the clipboard text to the book annotation.',
      'Аннотация из скопированного текста (меню ⋮): добавляет текст из буфера обмена в аннотацию книги.'
    ),
  ]),
  HelpTopic(
      Icons.hub_outlined,
      ('Story map', 'Карта истории'),
      id: 'story-map',
      [
    (
      'Open it with the Story map button (three linked dots) on the book screen (on a narrow screen it is in the ⋮ menu), or with the button on the cover in the Info tab. The map is built automatically from your text: names that keep their capital letter inside a sentence become people, and it counts who appears in which section. Nothing leaves your device unless you use "Improve with AI" (below).',
      'Откройте её кнопкой «Карта истории» (три связанные точки) на экране книги (на узком экране она в меню ⋮) или кнопкой на обложке во вкладке «Инфо». Карта строится сама по вашему тексту: слова, которые остаются с заглавной буквы внутри предложения, становятся героями, и считается, кто в каких разделах встречается. Ничего не покидает ваше устройство, если вы не пользуетесь «Улучшить с ИИ» (ниже).'
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
      'Improve with AI (⋮ menu): asks your AI provider to propose places, events and lore the map lacks, and labels for ties such as "brother of". The text of the book and the names on your map go to your provider, in as many requests as the size needs, after you confirm. Every proposal is checked against the text and shown for you to accept (✓) or reject (✕); ties sit under the place they need, accepting a tie adds its place, and rejecting a place drops its ties. The chips at the top switch Places, Events, Lore and Ties on and off, and "Accept all" applies only to what is showing. Nothing reaches the map unless you accept it.',
      'Улучшить с ИИ (меню ⋮): просит вашего ИИ-провайдера предложить места, события и мир, которых нет на карте, и подписи для связей, например «брат». Текст книги и имена с вашей карты уходят провайдеру, в нужном по размеру числе запросов, после вашего подтверждения. Каждое предложение сверяется с текстом и показывается вам: принять (✓) или отклонить (✕); связи стоят под нужным местом, принятие связи добавляет и место, а отклонение места убирает его связи. Метки сверху включают и выключают Места, События, Мир и Связи, а «Принять все» действует только на видимое. На карту ничего не попадает, пока вы не примете.',
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
  HelpTopic(Icons.save_outlined, ('Saving & export', 'Сохранение и экспорт'), icons: {
    0: Icons.ios_share,
    1: Icons.auto_awesome,
    2: Icons.more_vert,
    3: Icons.more_vert,
  }, [
    (
      '"Save & export" (top right of the book screen) opens one menu: "Save in the app" keeps the book in the app\'s private workspace, and the other entries export a file. It also shows whether you have unsaved changes (orange dot) or everything is saved (green tick). On a narrow screen the button is just the share icon.',
      '«Сохранить и экспорт» (справа вверху на экране книги) открывает одно меню: «Сохранить в приложении» хранит книгу в закрытом рабочем пространстве приложения, остальные пункты создают файл. Там же видно, есть ли несохранённые изменения (оранжевая точка) или всё сохранено (зелёная галочка). На узком экране кнопка — только значок «поделиться».'
    ),
    (
      'Auto-save (✨ in the book screen, or in Settings) also saves when you leave the editor or put the app in the background. Green means on.',
      'Автосохранение (✨ на экране книги или в настройках) также сохраняет при выходе из редактора и сворачивании приложения. Зелёный значок — включено.'
    ),
    (
      'Find and replace (⋮ menu on the book screen) works on the whole book: text only, never links or pictures. "Add another book" (also in the ⋮ menu) appends the chapters of an .fb2, .epub, .zip or .txt file after yours, with its pictures and footnotes; your cover and details stay.',
      'Поиск и замена (меню ⋮ на экране книги) работают по всей книге: только текст, ссылки и картинки не затрагиваются. «Добавить другую книгу» (тоже в меню ⋮) дописывает главы из файла .fb2, .epub, .zip или .txt после ваших вместе с картинками и сносками; ваша обложка и данные остаются.'
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
  HelpTopic(Icons.mic_none, ('Voice input', 'Голосовой ввод'), id: 'voice-input', icons: {
    2: Icons.mic_none,
  }, [
    (
      'Dictation is off until you switch on "Voice input" in Settings (Android only). Then a microphone button appears in the paragraph editor\'s format bar, and beside Title, Author, Keywords, Annotation, Find and Replace, and the Ask question box. Keys and addresses never get one.',
      'Диктовка выключена, пока вы не включите «Голосовой ввод» в настройках (только Android). Тогда кнопка микрофона появляется в панели форматирования редактора абзаца и рядом с полями «Название», «Автор», «Ключевые слова», «Аннотация», «Найти», «Заменить» и вопросом в «Спросить о книге». У ключей и адресов её нет.'
    ),
    (
      'The first tap offers a one-time download of the speech model (about 375 MB, Wi-Fi recommended). Speech is recognised on your device by that model: no audio and no words are sent anywhere, and no internet is needed after the download.',
      'Первое нажатие предлагает один раз скачать речевую модель (около 375 МБ, лучше по Wi-Fi). Речь распознаётся на вашем устройстве этой моделью: ни звук, ни слова никуда не отправляются, а после загрузки интернет не нужен.'
    ),
    (
      'Tap the microphone, speak, tap the stop button to finish. The words are inserted where the cursor or selection was when you started, as one step you can undo. The paragraph is locked while recording and transcribing.',
      'Нажмите микрофон, говорите, нажмите «стоп», чтобы закончить. Слова вставляются туда, где был курсор или выделение при старте, одним шагом, который можно отменить. Пока идёт запись и распознавание, абзац заблокирован.'
    ),
    (
      'One recording lasts up to 5 minutes and is transcribed piece by piece while you speak. A countdown shows in the last 5 seconds; at the limit recording stops by itself and what you said is still inserted. Tap the microphone again to carry on.',
      'Одна запись длится до 5 минут и распознаётся по частям, пока вы говорите. В последние 5 секунд идёт обратный отсчёт; по достижении лимита запись останавливается сама, а сказанное всё равно вставляется. Нажмите микрофон снова, чтобы продолжить.'
    ),
    (
      'English, Russian and Hebrew are recognised. The language is detected from each recording, whatever the language of the book, so speak one language per recording. If the microphone is denied, allow it for the app in the phone settings. A recording is discarded if the app goes to the background.',
      'Распознаются английский, русский и иврит. Язык определяется по каждой записи, независимо от языка книги, поэтому говорите на одном языке за запись. Если доступ к микрофону запрещён, разрешите его для приложения в настройках телефона. Если приложение уходит в фон, запись отбрасывается.'
    ),
  ]),
  HelpTopic(Icons.settings_outlined, ('Settings', 'Настройки'), icons: {
    0: Icons.edit_outlined,
    1: Icons.image_outlined,
    2: Icons.language,
    3: Icons.mic_none,
    4: Icons.save_outlined,
  }, [
    (
      'Editing: auto-save, the editor font size and page margins.',
      'Редактирование: автосохранение, размер шрифта и поля страницы.'
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
      'Voice input (Android): switch on dictation with the microphone. See "Voice input" above.',
      'Голосовой ввод (Android): включает диктовку с микрофона. См. «Голосовой ввод» выше.'
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

/// The tips of [t] that mention [query] (any case, English or Russian): all of
/// them when the title matches, none when nothing does.
List<(String, String)> matchingTips(HelpTopic t, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return t.tips;
  bool has((String, String) s) => s.$1.toLowerCase().contains(q) || s.$2.toLowerCase().contains(q);
  if (has(t.title)) return t.tips;
  return [for (final tip in t.tips) if (has(tip)) tip];
}

class HelpScreen extends StatefulWidget {
  final AppService service;

  /// The id of a [HelpTopic] to show first and open.
  final String? topic;
  const HelpScreen(this.service, {this.topic, super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The requested topic first, so it is in view when it opens.
  List<HelpTopic> get _ordered {
    final topic = widget.topic;
    return [
      ...helpTopics.where((x) => topic != null && x.id == topic),
      ...helpTopics.where((x) => topic == null || x.id != topic),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = widget.service;
    final topic = widget.topic;
    final query = _search.text.trim();
    final shown = [
      for (final t in _ordered)
        if (matchingTips(t, query) case final tips when query.isEmpty || tips.isNotEmpty) (t, tips)
    ];
    return Scaffold(
      appBar: appBarFor(context, title: Text(tr(service, 'Help', 'Справка'))),
      body: PageBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                key: const ValueKey('help-search'),
                controller: _search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: tr(service, 'Search help, e.g. footnote', 'Поиск по справке, напр. сноска'),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: tr(service, 'Clear', 'Очистить'),
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(_search.clear)),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(tr(service, 'Nothing found.', 'Ничего не найдено.'),
                    style: theme.textTheme.bodyMedium),
              ),
            for (final (t, tips) in shown)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  // a new key per search so matching topics open
                  key: ValueKey('${t.title.$1}|$query'),
                  initiallyExpanded: query.isNotEmpty || (topic != null && t.id == topic),
                  leading: Icon(t.icon, color: theme.colorScheme.primary),
                  title: Text(tr(service, t.title.$1, t.title.$2),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final tip in tips)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (t.icons[t.tips.indexOf(tip)] case final icon?)
                                Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Icon(icon, size: 20, color: theme.colorScheme.primary))
                              else
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
