import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/models/story_map.model.dart';
import 'package:quill_fb2/services/fb2.service.dart';
import 'package:quill_fb2/services/story_map_analyzer.dart';
import 'package:quill_fb2/utils/common.dart';

/// A made-up story of nine sections. Who appears where is known, so tests can check the map:
/// Gideon is missing from the middle act, Gabriel from the first.
///   Артур Рэйм (every act), Эвелин Ларк, Гидеон Кросс, Габриэль Вейн, Мэтью, Сивилла Векс,
///   Исайя, Капитан Брент.
List<StorySection> sampleStory() {
  const cast = {
    'A': 'Артур Рэйм', 'G': 'Габриэль Вейн', 'E': 'Эвелин Ларк', 'K': 'Гидеон Кросс',
    'M': 'Мэтью', 'S': 'Сивилла Векс', 'I': 'Исайя', 'B': 'Капитан Брент',
  };
  const places = ['библиотеке', 'саду', 'старом доме', 'порту', 'гостиной'];
  const templates = [
    'Поздним вечером в {p} {a} долго молчал, пока {b} рассказывал о прошлом.',
    '— Ты ничего не понимаешь, — сказал {a}, и {b} только покачал головой.',
    'Никто не заметил, как {a} вышел из {p} вслед за {b}.',
    'На рассвете {a} встретил {b} у ворот, и разговор вышел тяжёлым.',
    'Тем временем {a} перечитывал старое письмо в {p}.',
  ];
  const scenes = <(String, String)>[
    ('Приезд', 'AEM'), ('Письмо', 'AEKM'), ('Порт', 'AKB'),
    ('Ужин', 'AGEM'), ('Подвал', 'AGS'), ('Допрос', 'AGGEI'),
    ('Погоня', 'AKEB'), ('Признание', 'AKGE'), ('Рассвет', 'AEKI'),
  ];
  return [
    for (var s = 0; s < scenes.length; s++)
      StorySection('sample-$s', scenes[s].$1, [
        for (var p = 0; p < 5; p++)
          '<p>${templates[(s + p) % templates.length].replaceAll('{p}', places[(s + p) % places.length]).replaceAll('{a}', cast[scenes[s].$2[p % scenes[s].$2.length]]!).replaceAll('{b}', cast[scenes[s].$2[(p + 1) % scenes[s].$2.length]]!)}</p>'
      ])
  ];
}

/// A real book whose sections are [story], as the app would have after opening a file.
Future<ProjectModel> storyBook([List<StorySection>? story]) async {
  final book = ProjectModel.fromJson(await Fb2Service().convertXmlToJson(newBookXml('Story', 'x')));
  book.section.clear();
  for (final s in story ?? sampleStory()) {
    final sec = book.addSection(s.title);
    sec.sectionId = s.id;
    sec.p = List.of(s.paragraphs);
  }
  return book;
}

/// Index of the entity called [name] in [m].
int indexOfEntity(StoryMap m, String name) => m.cast.indexWhere((c) => c.name == name);
