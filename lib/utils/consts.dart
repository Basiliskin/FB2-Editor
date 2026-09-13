import 'dart:convert';

import 'package:flutter/material.dart';

const THEME_COLOR = 0xFFcFcF8d;
const START_SCREEN_COLOR = Color(THEME_COLOR);
const LIST_HEADER_COLOR = Color(THEME_COLOR);
const PROGRESSBAR_COLOR = Color(0xFF81b7de);
const MENU_COLOR = Color(THEME_COLOR);
const BUTTON_COLOR = Color(THEME_COLOR);
const LABEL_ODD_COLOR = Color(0xFFe0d9c3);
const LABEL_EVEN_COLOR = Color(0xFFe0cc8d);
const LIST_BORDER_COLOR = Color(0xFFe0cc8d);
const double DLIST_ITEM_HEIGHT = 180;
const double DLIST_ITEM_WIDTH = 80;
const STAR_COLOR = Colors.orangeAccent;
const STAR_NOT_COLOR = Color(0xFFe0cc8d);

Map<int, Color> colorPalette = {
  50: Color.fromRGBO(4, 131, 184, .1),
  100: Color.fromRGBO(4, 131, 184, .2),
  200: Color.fromRGBO(4, 131, 184, .3),
  300: Color.fromRGBO(4, 131, 184, .4),
  400: Color.fromRGBO(4, 131, 184, .5),
  500: Color.fromRGBO(4, 131, 184, .6),
  600: Color.fromRGBO(4, 131, 184, .7),
  700: Color.fromRGBO(4, 131, 184, .8),
  800: Color.fromRGBO(4, 131, 184, .9),
  900: Color.fromRGBO(4, 131, 184, 1),
};

enum LangTranslateItems {
  bookTitle,
  authorFirst,
  authorMid,
  authorLast,
  authorHomePage,
  authorId,
  authorNickname,
  settingsSaved,
  initializing,
  bookPageInfo,
  bookPageSection,
  bookPagePromptEnterName,
  buttonSave,
  buttonCancel,
  messageCreated,
  messageSaved,
  hintMessage,
  messagePlease,
  bookGenre,
  bookSequence,
  bookAnnotation,
  messageError,
  messageLoading,
  appTitle,
  autoSave,
  buttonShowPageImage,
  imageSize,
  imageQuality,
  fontSize,
  titleLanguage,
  buttonLoadBook,
  bookVersion,
  bookId
}

const LANGUAGES = {"eng": "English", "ru": "Русский"};

const LANG_TRANSLATE = {
  "eng": {
    LangTranslateItems.settingsSaved: "Settings Saved",
    LangTranslateItems.initializing: "Initializing",
    LangTranslateItems.bookTitle: "Book Title",
    LangTranslateItems.authorFirst: "First",
    LangTranslateItems.authorMid: "Middle",
    LangTranslateItems.authorLast: "Last",
    LangTranslateItems.authorHomePage: "Home Page",
    LangTranslateItems.authorId: "Author ID",
    LangTranslateItems.authorNickname: "Nick Name",
    LangTranslateItems.bookPageInfo: "Info",
    LangTranslateItems.bookPageSection: "Book",
    LangTranslateItems.bookPagePromptEnterName: 'Enter Section Name:',
    LangTranslateItems.buttonSave: "Save",
    LangTranslateItems.buttonCancel: "Cancel",
    LangTranslateItems.messageCreated: "Created",
    LangTranslateItems.messageSaved: "Saved",
    LangTranslateItems.hintMessage: "Enter your",
    LangTranslateItems.messagePlease: 'Please enter some text',
    LangTranslateItems.bookGenre: 'Enter Genre',
    LangTranslateItems.bookSequence: 'Enter Sequence',
    LangTranslateItems.bookAnnotation: 'Enter Annotation',
    LangTranslateItems.messageError: "Error",
    LangTranslateItems.messageLoading: "Loading",
    LangTranslateItems.appTitle: "FB2 Editor",
    LangTranslateItems.autoSave: "Auto save book",
    LangTranslateItems.buttonShowPageImage: "Show page image",
    LangTranslateItems.imageSize: "Image size",
    LangTranslateItems.imageQuality: "Image Quality",
    LangTranslateItems.fontSize: "Font Size",
    LangTranslateItems.titleLanguage: "Language",
    LangTranslateItems.buttonLoadBook: "Load Book",
    LangTranslateItems.bookVersion: "Book Version",
    LangTranslateItems.bookId: "Book Id"
  },
  "ru": {
    LangTranslateItems.settingsSaved: "Настройки сохранены",
    LangTranslateItems.initializing: "Инициализация",
    LangTranslateItems.bookTitle: "Название книги",
    LangTranslateItems.authorFirst: "Имя",
    LangTranslateItems.authorMid: "Oтчество",
    LangTranslateItems.authorLast: "Фамилия",
    LangTranslateItems.authorHomePage: "Главная",
    LangTranslateItems.authorId: "Идентификатор автора",
    LangTranslateItems.authorNickname: "Псевдоним",
    LangTranslateItems.bookPageInfo: "Информация",
    LangTranslateItems.bookPageSection: "Книга",
    LangTranslateItems.bookPagePromptEnterName: 'Введите название раздела:',
    LangTranslateItems.buttonSave: "Сохранять",
    LangTranslateItems.buttonCancel: "Отмена",
    LangTranslateItems.messageCreated: "Созданный",
    LangTranslateItems.messageSaved: "Сохранено",
    LangTranslateItems.hintMessage: "Введите свой",
    LangTranslateItems.messagePlease: 'Пожалуйста, введите текст',
    LangTranslateItems.bookGenre: 'Введите жанр',
    LangTranslateItems.bookSequence: 'Книжная серия',
    LangTranslateItems.bookAnnotation: 'Введите аннотацию',
    LangTranslateItems.messageError: "Ошибка",
    LangTranslateItems.messageLoading: "Загрузка",
    LangTranslateItems.appTitle: "Редактор художественной литературы",
    LangTranslateItems.autoSave: "Автосохранение книги",
    LangTranslateItems.buttonShowPageImage: "Показать изображение страницы",
    LangTranslateItems.imageSize: "Ширина изображения",
    LangTranslateItems.imageQuality: "Качество изображения",
    LangTranslateItems.fontSize: "Размер шрифта",
    LangTranslateItems.titleLanguage: "Язык",
    LangTranslateItems.buttonLoadBook: "Загрузить книгу",
    LangTranslateItems.bookVersion: "Версия книги",
    LangTranslateItems.bookId: "Идентификатор книги"
  }
};

class TranslationService {
  Map<String, Map> _languages = LANG_TRANSLATE;
  getTranslations(String lang) {
    return _languages[lang] ?? {};
  }
}

const BOOK_EXT = '.fb2';
const MAX_BOOK_IN_HISTORY = 10;

splitStringByEof(String text) {
  LineSplitter ls = new LineSplitter();
  return ls.convert(text);
}

const MAX_SECTION_LENGTH = 500;
