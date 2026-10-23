import 'package:flutter/material.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/ui/widgets.dart';

/// One help topic: a heading with a few short tips, each an (en, ru) pair.
class HelpTopic {
  final IconData icon;
  final (String, String) title;
  final List<(String, String)> tips;
  const HelpTopic(this.icon, this.title, this.tips);
}

const helpTopics = <HelpTopic>[
  HelpTopic(Icons.local_library_outlined, ('Library', 'Библиотека'), [
    (
      'Tap "Load book" to pick an .fb2 file, or a .zip archive that contains one.',
      'Нажмите «Загрузить книгу», чтобы выбрать файл .fb2 или архив .zip с книгой.'
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
  ]),
  HelpTopic(Icons.save_outlined, ('Saving & export', 'Сохранение и экспорт'), [
    (
      'Save (💾) writes the book to the app\'s private workspace.',
      'Сохранить (💾) записывает книгу в закрытое рабочее пространство приложения.'
    ),
    (
      'Auto-save (✨ in the book screen, or in Settings) also saves when you leave the editor or put the app in the background. Green means on.',
      'Автосохранение (✨ на экране книги или в настройках) также сохраняет при выходе из редактора и сворачивании приложения. Зелёный значок — включено.'
    ),
    (
      'Export saves a ready .fb2 file where you choose (in the browser it downloads the file). The file is named "Author - Title.fb2" and always contains your latest edits.',
      'Экспорт сохраняет готовый файл .fb2 в выбранное место (в браузере файл скачивается). Файл называется «Автор - Название.fb2» и всегда содержит последние правки.'
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
Future<void> openHelp(BuildContext context, AppService service) =>
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => HelpScreen(service)));

class HelpScreen extends StatelessWidget {
  final AppService service;
  const HelpScreen(this.service, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: appBarFor(context, title: Text(tr(service, 'Help', 'Справка'))),
      body: PageBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            for (final topic in helpTopics)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  leading: Icon(topic.icon, color: t.colorScheme.primary),
                  title: Text(tr(service, topic.title.$1, topic.title.$2),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final tip in topic.tips)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('•  '),
                              Expanded(
                                  child: Text(tr(service, tip.$1, tip.$2),
                                      style: t.textTheme.bodyMedium)),
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
