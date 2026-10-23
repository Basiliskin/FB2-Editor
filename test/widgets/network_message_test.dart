import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/widgets/network_message.dart';

void main() {
  final s = AppService();

  test('on web it names CORS as a likely cause and points to Android', () {
    final m = networkMessage(s, web: true);
    expect(m, contains('CORS'));
    expect(m, contains('Android app'));
  });

  test('on Android a plain http base URL gets the https hint', () {
    expect(networkMessage(s, web: false, baseUrl: 'http://192.168.1.5:11434/v1'),
        contains('try https'));
  });

  test('otherwise it is the plain message', () {
    expect(networkMessage(s, web: false, baseUrl: 'https://x/v1'),
        'Could not reach the provider');
    expect(networkMessage(s, web: false), 'Could not reach the provider');
  });

  test('speaks Russian when the language is ru', () {
    s.getSettings()['language'] = 'ru';
    addTearDown(() => s.getSettings()['language'] = 'eng');
    expect(networkMessage(s, web: true), contains('CORS'));
    expect(networkMessage(s, web: false), 'Нет связи с провайдером');
  });
}
