import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/pages/start_page.dart';
import 'package:quill_fb2/routes.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/widgets/loading.dialog.dart';

class _FakeService extends AppService {
  int inits = 0;
  bool failInit = false;

  @override
  init() async {
    inits++;
    if (failInit) throw StateError('init failed');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _FakeService service;
  late List<String> permissionCalls;
  late int storageStatus; // PermissionStatus index: 0 denied, 1 granted
  late bool permissionFails;

  setUp(() {
    service = _FakeService();
    permissionCalls = [];
    storageStatus = 1;
    permissionFails = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      permissionCalls.add(call.method);
      if (permissionFails) throw PlatformException(code: 'nope');
      if (call.method == 'checkPermissionStatus') return storageStatus;
      if (call.method == 'requestPermissions') {
        return {for (final p in call.arguments as List) p as int: 1};
      }
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: StartScreen(service),
      routes: {Routes.screenHome: (_) => const Text('home')},
    ));
  }

  testWidgets('shows the initializing progress bar', (tester) async {
    await pump(tester);
    expect(find.byType(ModalRoundedProgressBar), findsOneWidget);
    expect(find.text('Initializing'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('initialises the service then replaces itself with home',
      (tester) async {
    await pump(tester);
    expect(service.inits, 0);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(service.inits, 1);
    expect(find.text('home'), findsOneWidget);
    expect(find.byType(StartScreen), findsNothing);
    expect(permissionCalls, ['checkPermissionStatus']);
  });

  testWidgets('requests storage permission when it was denied',
      (tester) async {
    storageStatus = 0;
    await pump(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(permissionCalls, contains('requestPermissions'));
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('shows the error and stays when init fails', (tester) async {
    service.failInit = true;
    await pump(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.textContaining('init failed'), findsOneWidget);
    expect(find.byType(StartScreen), findsOneWidget);
    expect(find.text('home'), findsNothing);
  });

  testWidgets('shows the error when the permission check fails',
      (tester) async {
    permissionFails = true;
    await pump(tester);
    await tester.pump();
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.byType(StartScreen), findsOneWidget);
  });

  testWidgets('hot reload starts the loading again', (tester) async {
    await pump(tester);
    tester.binding.reassembleApplication();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(service.inits, greaterThanOrEqualTo(1));
    expect(permissionCalls.length, greaterThanOrEqualTo(2));
  });
}
