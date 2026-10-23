import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/widgets/easy_form_kit/easy_form_kit.dart';
import 'package:quill_fb2/widgets/easy_form_kit/src/buttons/action_button.dart';

/// Hosts [child] in an [EasyForm] with a never-firing save trigger.
Widget _host(
  Widget child, {
  Key? key,
  EasyFormAdaptivity adaptivity = EasyFormAdaptivity.auto,
  EasyAutovalidateMode autovalidateMode = EasyAutovalidateMode.disabled,
  EasyFormFieldSaveCallback? onSave,
  EasyFormFieldSavedCallback? onSaved,
  EasyFormChangeCallback? onChanged,
  Stream<void>? trigger,
  TargetPlatform? platform,
}) {
  return MaterialApp(
    theme: ThemeData(platform: platform),
    home: Scaffold(
      body: EasyForm(
        key: key,
        adaptivity: adaptivity,
        autovalidateMode: autovalidateMode,
        triggerSave: trigger ?? const Stream<void>.empty(),
        onSave: onSave,
        onSaved: onSaved,
        onChanged: onChanged,
        child: SingleChildScrollView(child: child),
      ),
    ),
  );
}

String? _required(String? v, [Map<String, dynamic>? values]) =>
    (v == null || v.isEmpty) ? 'required' : null;

void main() {
  group('EasyForm adaptivity', () {
    final expected = {
      TargetPlatform.android: EasyFormAdaptivity.material,
      TargetPlatform.fuchsia: EasyFormAdaptivity.material,
      TargetPlatform.linux: EasyFormAdaptivity.material,
      TargetPlatform.windows: EasyFormAdaptivity.material,
      TargetPlatform.iOS: EasyFormAdaptivity.cupertino,
      TargetPlatform.macOS: EasyFormAdaptivity.cupertino,
    };
    expected.forEach((platform, want) {
      testWidgets('auto on $platform resolves to $want', (tester) async {
        final key = GlobalKey<EasyFormState>();
        await tester.pumpWidget(
            _host(const SizedBox(), key: key, platform: platform));
        expect(key.currentState!.adaptivity, want);
      });
    });

    testWidgets('explicit adaptivity is kept', (tester) async {
      final key = GlobalKey<EasyFormState>();
      await tester.pumpWidget(_host(const SizedBox(),
          key: key, adaptivity: EasyFormAdaptivity.cupertino));
      expect(key.currentState!.adaptivity, EasyFormAdaptivity.cupertino);
      expect(key.currentState!.fields, isEmpty);
      expect(key.currentState!.isSaving.value, isFalse);
    });
  });

  group('EasyForm state', () {
    testWidgets('values, save, onSaved and isSaving', (tester) async {
      final key = GlobalKey<EasyFormState>();
      final completer = Completer<dynamic>();
      final saved = <dynamic>[];
      final fieldSaved = <String>[];
      await tester.pumpWidget(_host(
        EasyTextFormField(
            name: 'a', initialValue: 'x', onSaved: (v) => fieldSaved.add(v!)),
        key: key,
        onSave: (values, form) => completer.future,
        onSaved: (data, values, form) => saved.add([data, values]),
      ));
      expect(key.currentState!.values(), {'a': 'x'});
      final f = key.currentState!.save();
      await tester.pump();
      expect(key.currentState!.isSaving.value, isTrue);
      completer.complete('result');
      expect(await f, isTrue);
      expect(key.currentState!.isSaving.value, isFalse);
      expect(fieldSaved, ['x']);
      expect(saved.single, [
        'result',
        {'a': 'x'}
      ]);
    });

    testWidgets('onSaved receives the values when onSave returns null',
        (tester) async {
      final key = GlobalKey<EasyFormState>();
      final saved = <dynamic>[];
      await tester.pumpWidget(_host(
        EasyTextFormField(name: 'a', initialValue: 'x'),
        key: key,
        onSave: (values, form) async => null,
        onSaved: (data, values, form) => saved.add(data),
      ));
      await key.currentState!.save();
      expect(saved.single, {'a': 'x'});
    });

    testWidgets('save without callbacks still succeeds', (tester) async {
      final key = GlobalKey<EasyFormState>();
      await tester.pumpWidget(_host(const SizedBox(), key: key));
      expect(await key.currentState!.save(), isTrue);
    });

    testWidgets('invalid form is not saved and focuses the bad field',
        (tester) async {
      final key = GlobalKey<EasyFormState>();
      var saves = 0;
      await tester.pumpWidget(_host(
        Column(children: [
          EasyTextFormField(name: 'a', validator: _required),
          EasyTextFormField(name: 'b', initialValue: 'ok'),
        ]),
        key: key,
        onSave: (v, f) async => saves++,
      ));
      expect(await key.currentState!.save(), isFalse);
      await tester.pump();
      expect(saves, 0);
      expect(find.text('required'), findsOneWidget);
      final bad =
          key.currentState!.fields.firstWhere((f) => f.name == 'a');
      expect(bad.focusNode.hasFocus, isTrue);
      // ignoreValidate bypasses validation
      expect(await key.currentState!.save(true), isTrue);
      expect(saves, 1);
    });

    testWidgets('reset restores initial values and notifies', (tester) async {
      final key = GlobalKey<EasyFormState>();
      final changes = <EasyFormFieldState?>[];
      await tester.pumpWidget(_host(
        EasyTextFormField(name: 'a', initialValue: 'x', validator: _required),
        key: key,
        onChanged: changes.add,
      ));
      await tester.enterText(find.byType(TextField), 'changed');
      await tester.pump();
      expect(key.currentState!.values(), {'a': 'changed'});
      changes.clear();
      key.currentState!.reset();
      await tester.pump();
      expect(key.currentState!.values(), {'a': 'x'});
      expect(find.text('x'), findsOneWidget);
      expect(changes, [null]);
    });

    testWidgets('autovalidate always validates on build', (tester) async {
      await tester.pumpWidget(_host(
        EasyTextFormField(name: 'a', validator: _required),
        autovalidateMode: EasyAutovalidateMode.always,
      ));
      // fields register during the first build; the next form build validates
      await tester.enterText(find.byType(TextField), 'x');
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      await tester.pump();
      expect(find.text('required'), findsOneWidget);
    });

    testWidgets('autovalidate onUserInteraction waits for interaction',
        (tester) async {
      await tester.pumpWidget(_host(
        EasyTextFormField(name: 'a', initialValue: 'x', validator: _required),
        autovalidateMode: EasyAutovalidateMode.onUserInteraction,
      ));
      expect(find.text('required'), findsNothing);
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      await tester.pump();
      expect(find.text('required'), findsOneWidget);
    });

    testWidgets('rebuildOnChange false skips the rebuild', (tester) async {
      final changes = <EasyFormFieldState?>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EasyForm(
            rebuildOnChange: false,
            triggerSave: const Stream<void>.empty(),
            onChanged: changes.add,
            child: EasyTextFormField(name: 'a'),
          ),
        ),
      ));
      await tester.enterText(find.byType(TextField), 'z');
      expect(changes, hasLength(1));
    });

    testWidgets('triggerSave stream saves the form', (tester) async {
      final ctl = StreamController<void>.broadcast();
      addTearDown(ctl.close);
      var saves = 0;
      await tester.pumpWidget(
          _host(const SizedBox(), trigger: ctl.stream, onSave: (v, f) async => saves++));
      ctl.add(null);
      await tester.pump();
      expect(saves, 1);
    });

    testWidgets('triggerSave swallows errors', (tester) async {
      final ctl = StreamController<void>.broadcast();
      addTearDown(ctl.close);
      final logged = <String>[];
      await runZoned(
        () async {
          await tester.pumpWidget(_host(const SizedBox(), trigger: ctl.stream));
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) {
            if (line == 'EasyFormState.triggerSave') {
              throw StateError('boom');
            }
            logged.add(line);
          },
        ),
      );
      ctl.add(null);
      await tester.pump();
      expect(logged.single, contains('boom'));
    });

    testWidgets('onWillPop is wired and the scope exposes its form',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: EasyForm(
          triggerSave: const Stream<void>.empty(),
          onWillPop: () async => false,
          child: const SizedBox(),
        ),
      ));
      final scope = tester.widget(find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_FormScope'));
      expect((scope as dynamic).form, isA<EasyForm>());
    });

    testWidgets('EasyForm.of is null outside a form', (tester) async {
      EasyFormState? found = EasyFormState();
      await tester.pumpWidget(Builder(builder: (context) {
        found = EasyForm.of(context);
        return const SizedBox();
      }));
      expect(found, isNull);
    });
  });

  group('EasyFormField', () {
    Widget field({
      String? initial,
      EasyFormFieldValidator<String?>? validator,
      EasyAutovalidateMode mode = EasyAutovalidateMode.disabled,
      bool enabled = true,
      FocusNode? focusNode,
      GlobalKey<EasyFormFieldState<String?>>? key,
      void Function(EasyFormFieldState<String?>)? capture,
    }) =>
        EasyFormField<String?>(
          key: key,
          name: 'f',
          initialValue: initial,
          validator: validator,
          autovalidateMode: mode,
          enabled: enabled,
          focusNode: focusNode,
          builder: (state) {
            capture?.call(state);
            return Focus(
                focusNode: state.focusNode,
                child: Text('v=${state.value} e=${state.errorText}'));
          },
        );

    testWidgets('inside a form: validate, isValid, reset, saveForm, focus',
        (tester) async {
      final fkey = GlobalKey<EasyFormFieldState<String?>>();
      final saves = <Map<String, dynamic>>[];
      await tester.pumpWidget(_host(
        field(initial: '', validator: _required, key: fkey),
        onSave: (v, f) async => saves.add(v),
      ));
      final s = fkey.currentState!;
      expect(s.isValid, isFalse);
      expect(s.hasError, isTrue);
      expect(s.validate(), isFalse);
      await tester.pump();
      expect(find.text('v= e=required'), findsOneWidget);

      s.didChange('abc');
      await tester.pump();
      expect(s.isValid, isTrue);
      expect(s.validate(), isTrue);
      s.setValue('direct');
      expect(s.value, 'direct');

      s.reset();
      await tester.pump();
      expect(s.value, '');
      expect(s.errorText, isNull);

      s.didChange('ok');
      expect(await s.saveForm(), isTrue);
      expect(saves.single, {'f': 'ok'});

      // focus when not focused, then again when focused
      s.focus();
      await tester.pump();
      expect(s.focusNode.hasFocus, isTrue);
      s.focus();
      await tester.pump();
      await tester.pump();
      expect(s.focusNode.hasFocus, isTrue);
      s.unfocus();
      await tester.pump();
      expect(s.focusNode.hasFocus, isFalse);
    });

    testWidgets('supplied focusNode is used', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      final fkey = GlobalKey<EasyFormFieldState<String?>>();
      await tester.pumpWidget(_host(field(focusNode: node, key: fkey)));
      expect(fkey.currentState!.focusNode, same(node));
    });

    testWidgets('outside a form: saveForm is false and nothing registers',
        (tester) async {
      final fkey = GlobalKey<EasyFormFieldState<String?>>();
      await tester.pumpWidget(MaterialApp(
          home: field(initial: 'a', validator: _required, key: fkey)));
      final s = fkey.currentState!;
      expect(await s.saveForm(), isFalse);
      expect(s.isValid, isTrue);
      s.didChange('b');
      s.reset();
      await tester.pump();
      expect(s.value, 'a');
    });

    testWidgets('autovalidate always validates on build', (tester) async {
      await tester.pumpWidget(_host(field(
          initial: '',
          validator: _required,
          mode: EasyAutovalidateMode.always)));
      expect(find.text('v= e=required'), findsOneWidget);
    });

    testWidgets('autovalidate onUserInteraction validates after a change',
        (tester) async {
      final fkey = GlobalKey<EasyFormFieldState<String?>>();
      await tester.pumpWidget(_host(field(
          initial: 'x',
          validator: _required,
          mode: EasyAutovalidateMode.onUserInteraction,
          key: fkey)));
      expect(find.text('v=x e=null'), findsOneWidget);
      fkey.currentState!.didChange('');
      await tester.pump();
      expect(find.text('v= e=required'), findsOneWidget);
    });

    testWidgets('disabled field skips autovalidation', (tester) async {
      await tester.pumpWidget(_host(field(
          initial: '',
          validator: _required,
          enabled: false,
          mode: EasyAutovalidateMode.always)));
      expect(find.text('v= e=null'), findsOneWidget);
    });
  });

  group('EasyCustomFormField', () {
    Widget custom({
      Key? key,
      ValueNotifier<int?>? controller,
      int? initial,
      bool rebuilder = false,
      bool getSet = false,
      ValueChanged<int>? onChanged,
      void Function(void Function(int))? capture,
    }) =>
        EasyCustomFormField<int, ValueNotifier<int?>>(
          key: key,
          name: 'n',
          controller: controller,
          initialValue: initial,
          controllerBuilder: (v) => ValueNotifier<int?>(v),
          controllerRebuilder:
              rebuilder ? (old) => ValueNotifier<int?>(old.value! * 100) : null,
          valueGet: getSet ? (c) => c.value : null,
          valueSet: getSet ? (c, v) => c.value = v : null,
          onChanged: onChanged,
          builder: (state, onChangedHandler) {
            capture?.call(onChangedHandler);
            return Text('n=${state.value}');
          },
        );

    testWidgets('own controller: change, onChanged, reset', (tester) async {
      final fkey = GlobalKey<EasyFormState>();
      final seen = <int>[];
      void Function(int)? push;
      await tester.pumpWidget(_host(
          custom(initial: 3, onChanged: seen.add, capture: (c) => push = c),
          key: fkey));
      expect(find.text('n=3'), findsOneWidget);
      push!(7);
      await tester.pump();
      expect(find.text('n=7'), findsOneWidget);
      expect(seen, [7]);
      expect(fkey.currentState!.values(), {'n': 7});
      fkey.currentState!.reset();
      await tester.pump();
      expect(find.text('n=3'), findsOneWidget);
    });

    testWidgets('custom valueGet / valueSet are used', (tester) async {
      void Function(int)? push;
      await tester.pumpWidget(
          _host(custom(initial: 1, getSet: true, capture: (c) => push = c)));
      push!(2);
      await tester.pump();
      expect(find.text('n=2'), findsOneWidget);
    });

    testWidgets('external controller drives the field', (tester) async {
      final c = ValueNotifier<int?>(1);
      addTearDown(c.dispose);
      await tester.pumpWidget(_host(custom(controller: c)));
      expect(find.text('n=1'), findsOneWidget);
      c.value = 9;
      await tester.pump();
      expect(find.text('n=9'), findsOneWidget);
      // unmount removes the listener
      await tester.pumpWidget(_host(const SizedBox()));
      c.value = 10;
    });

    testWidgets('swapping controllers', (tester) async {
      final c1 = ValueNotifier<int?>(1);
      final c2 = ValueNotifier<int?>(2);
      addTearDown(c1.dispose);
      addTearDown(c2.dispose);
      final k = GlobalKey();
      await tester.pumpWidget(_host(custom(key: k, controller: c1)));
      // external -> another external
      await tester.pumpWidget(_host(custom(key: k, controller: c2)));
      expect(find.text('n=2'), findsOneWidget);
      // external -> none, default rebuild from the old controller
      await tester.pumpWidget(_host(custom(key: k)));
      // none -> external
      await tester.pumpWidget(_host(custom(key: k, controller: c1)));
      expect(find.text('n=1'), findsOneWidget);
      // external -> none with a custom rebuilder
      await tester.pumpWidget(_host(custom(key: k, rebuilder: true)));
      await tester.pump();
    });
  });

  group('EasyTextFormField', () {
    testWidgets('onFieldSubmitted and saveOnSubmit', (tester) async {
      final submitted = <String>[];
      final saves = <Map<String, dynamic>>[];
      await tester.pumpWidget(_host(
        EasyTextFormField(
          name: 't',
          saveOnSubmit: true,
          onFieldSubmitted: submitted.add,
        ),
        onSave: (v, f) async => saves.add(v),
      ));
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(submitted, ['hello']);
      expect(saves.single, {'t': 'hello'});
    });

    testWidgets('submit without saveOnSubmit does not save', (tester) async {
      final saves = <Map<String, dynamic>>[];
      await tester.pumpWidget(_host(
        EasyTextFormField(name: 't'),
        onSave: (v, f) async => saves.add(v),
      ));
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(saves, isEmpty);
    });

    testWidgets('obscureText flips the smart-quote defaults', (tester) async {
      await tester.pumpWidget(
          _host(EasyTextFormField(name: 'p', obscureText: true)));
      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.smartDashesType, SmartDashesType.disabled);
      expect(tf.smartQuotesType, SmartQuotesType.disabled);
    });

    testWidgets('programmatic controller edits reach the form',
        (tester) async {
      final fk = GlobalKey<EasyFormState>();
      await tester.pumpWidget(
          _host(EasyTextFormField(name: 't', initialValue: 'a'), key: fk));
      final field = tester.widget<EasyTextFormField>(find.byType(EasyTextFormField));
      final c = field.recreateController(TextEditingController(text: 'old'));
      expect(c.text, 'old');
      c.dispose();
      expect(field.valueOf(TextEditingController(text: 'z')), 'z');
      fk.currentState!.fields.single.didChange('typed');
      await tester.pump();
      expect(find.text('typed'), findsOneWidget);
      fk.currentState!.reset();
      await tester.pump();
      expect(find.text('a'), findsOneWidget);
    });

    testWidgets('EasyTextFormField.builder renders custom UI', (tester) async {
      final fk = GlobalKey<EasyFormState>();
      await tester.pumpWidget(_host(
        EasyTextFormField.builder(
          name: 'b',
          initialValue: 'init',
          builder: (state, onChanged) => TextButton(
            onPressed: () => onChanged('pressed'),
            child: Text('b=${state.value}'),
          ),
        ),
        key: fk,
      ));
      expect(find.text('b=init'), findsOneWidget);
      await tester.tap(find.byType(TextButton));
      await tester.pump();
      expect(find.text('b=pressed'), findsOneWidget);
      expect(fk.currentState!.values(), {'b': 'pressed'});
      final field = tester
          .widget<EasyTextFormField>(find.byType(EasyTextFormField));
      final rebuilt =
          field.recreateController(TextEditingController(text: 'old'));
      expect(rebuilt.text, 'old');
      rebuilt.dispose();
    });
  });

  group('EasyFormGenericField', () {
    testWidgets('renders, reacts to controller, setting value calls onChange',
        (tester) async {
      final c = EasyFormFieldController<int>(1);
      addTearDown(c.dispose);
      final changes = <int?>[];
      final w = _Counter(controller: c, onChange: changes.add);
      await tester.pumpWidget(MaterialApp(home: w));
      expect(find.text('count=1'), findsOneWidget);
      await tester.tap(find.byType(TextButton));
      await tester.pump();
      expect(find.text('count=2'), findsOneWidget);
      expect(changes, [2]);
      expect(w.value, 2);

      final state = tester.state<EasyFormGenericFieldState<int>>(
          find.byType(_Counter));
      expect(state.controller, same(c));
      state.value = 5;
      await tester.pump();
      expect(state.value, 5);
      expect(find.text('count=5'), findsOneWidget);
    });

    testWidgets('swapping the controller moves the listener', (tester) async {
      final a = EasyFormFieldController<int>(1);
      final b = EasyFormFieldController<int>(10);
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await tester.pumpWidget(MaterialApp(home: _Counter(controller: a)));
      await tester.pumpWidget(MaterialApp(home: _Counter(controller: b)));
      expect(find.text('count=10'), findsOneWidget);
      b.value = 11;
      await tester.pump();
      expect(find.text('count=11'), findsOneWidget);
    });

    testWidgets('an unimplemented build throws', (tester) async {
      final c = EasyFormFieldController<int>(1);
      addTearDown(c.dispose);
      await tester.pumpWidget(MaterialApp(home: _Bare(controller: c)));
      expect(tester.takeException(), isA<UnimplementedError>());
    });

    test('fromValue constructor', () {
      final c = EasyFormFieldController<int>.fromValue(4);
      expect(c, isA<ValueNotifier<int?>>());
      c.dispose();
    });
  });

  group('buttons', () {
    testWidgets('save button saves and shows an indicator meanwhile',
        (tester) async {
      final completer = Completer<dynamic>();
      var saves = 0;
      await tester.pumpWidget(_host(
        EasyFormSaveButton.text('Save'),
        onSave: (v, f) {
          saves++;
          return completer.future;
        },
      ));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // locked while saving
      await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
      expect(saves, 1);
      completer.complete(null);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('cupertino save button', (tester) async {
      final completer = Completer<dynamic>();
      await tester.pumpWidget(_host(
        EasyFormSaveButton(child: const Text('Save')),
        adaptivity: EasyFormAdaptivity.cupertino,
        onSave: (v, f) => completer.future,
      ));
      await tester.tap(find.byType(CupertinoButton));
      await tester.pump();
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      completer.complete(null);
      await tester.pump();
    });

    testWidgets('save button custom builders', (tester) async {
      final completer = Completer<dynamic>();
      await tester.pumpWidget(_host(
        EasyFormSaveButton(
          child: const Text('Go'),
          indicatorSize: const Size(10, 10),
          indicatorBuilder: (c, s, a) => const Text('busy'),
          layoutBuilder: (c, body, ind) => Column(children: [body, ind]),
          builder: (c, key, child, onPressed, a) =>
              TextButton(onPressed: onPressed, child: child),
          padding: EdgeInsets.zero,
          alignment: Alignment.centerLeft,
        ),
        onSave: (v, f) => completer.future,
      ));
      await tester.tap(find.byType(TextButton));
      await tester.pump();
      expect(find.text('busy'), findsOneWidget);
      completer.complete(null);
      await tester.pump();
      expect(find.text('busy'), findsNothing);
    });

    testWidgets('reset button resets the form', (tester) async {
      final fk = GlobalKey<EasyFormState>();
      await tester.pumpWidget(_host(
        Column(children: [
          EasyTextFormField(name: 'a', initialValue: 'x'),
          EasyFormResetButton.text('Reset'),
        ]),
        key: fk,
      ));
      await tester.enterText(find.byType(TextField), 'y');
      await tester.tap(find.byType(OutlinedButton));
      await tester.pump();
      expect(fk.currentState!.values(), {'a': 'x'});
    });

    testWidgets('reset button cupertino and custom builder', (tester) async {
      await tester.pumpWidget(_host(
        EasyFormResetButton(child: const Text('R')),
        key: UniqueKey(),
        adaptivity: EasyFormAdaptivity.cupertino,
      ));
      expect(find.byType(CupertinoButton), findsOneWidget);
      await tester.pumpWidget(_host(EasyFormResetButton(
        child: const Text('R'),
        builder: (c, key, child, onPressed, a) =>
            TextButton(onPressed: onPressed, child: child),
      )));
      expect(find.byType(TextButton), findsOneWidget);
    });

    testWidgets('action button runs its action; renders nothing without form',
        (tester) async {
      var ran = 0;
      await tester.pumpWidget(_host(EasyFormActionButton(
        child: const Text('A'),
        action: (context, form) => ran++,
        lockOnSaving: false,
      )));
      await tester.tap(find.byType(ElevatedButton));
      expect(ran, 1);

      await tester.pumpWidget(_host(EasyFormActionButton(
        child: const Text('A'),
        builder: (c, key, child, onPressed, a) =>
            TextButton(onPressed: onPressed, child: child),
      )));
      await tester.tap(find.byType(TextButton)); // no action: no-op
      await tester.pumpWidget(_host(EasyFormActionButton(
          child: const Text('A'))));
      expect(find.byType(ElevatedButton), findsOneWidget);

      await tester.pumpWidget(_host(EasyFormActionButton(
        child: const Text('A'),
      ), key: UniqueKey(), adaptivity: EasyFormAdaptivity.cupertino));
      expect(find.byType(CupertinoButton), findsOneWidget);

      await tester.pumpWidget(MaterialApp(
          home: EasyFormActionButton(child: const Text('A'))));
      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('form button passes the form (or null)', (tester) async {
      EasyFormState? inside;
      EasyFormState? outside = EasyFormState();
      await tester.pumpWidget(_host(EasyFormButton(builder: (c, form) {
        inside = form;
        return const SizedBox();
      })));
      expect(inside, isNotNull);
      await tester.pumpWidget(MaterialApp(
          home: EasyFormButton(builder: (c, form) {
        outside = form;
        return const SizedBox();
      })));
      expect(outside, isNull);
    });
  });

  group('EasyFormSaveIndicator', () {
    testWidgets('returns the child outside a form', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: EasyFormSaveIndicator(child: const Text('c'))));
      expect(find.text('c'), findsOneWidget);
      expect(find.byType(Stack), findsNothing);
    });

    testWidgets('shows a dimmed child and indicator while saving',
        (tester) async {
      final fk = GlobalKey<EasyFormState>();
      final completer = Completer<dynamic>();
      await tester.pumpWidget(_host(
        EasyFormSaveIndicator(child: const Text('c')),
        key: fk,
        onSave: (v, f) => completer.future,
      ));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final f = fk.currentState!.save();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
          tester
              .widget<Opacity>(find.descendant(
                  of: find.byType(EasyFormSaveIndicator),
                  matching: find.byType(Opacity)))
              .opacity,
          EasyFormSaveIndicator.kChildOpacityOnSave);
      completer.complete(null);
      await f;
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('cupertino and custom builders', (tester) async {
      final fk = GlobalKey<EasyFormState>();
      final completer = Completer<dynamic>();
      await tester.pumpWidget(_host(
        EasyFormSaveIndicator(child: const Text('c')),
        key: fk,
        adaptivity: EasyFormAdaptivity.cupertino,
        onSave: (v, f) => completer.future,
      ));
      final f = fk.currentState!.save();
      await tester.pump();
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      completer.complete(null);
      await f;

      final completer2 = Completer<dynamic>();
      await tester.pumpWidget(_host(
        EasyFormSaveIndicator(
          child: const Text('c'),
          indicatorBuilder: (c, s, a) => const Text('spin'),
          layoutBuilder: (c, body, [ind]) =>
              Column(children: [body, if (ind != null) ind]),
        ),
        key: fk,
        onSave: (v, f) => completer2.future,
      ));
      final f2 = fk.currentState!.save();
      await tester.pump();
      expect(find.text('spin'), findsOneWidget);
      completer2.complete(null);
      await f2;
      await tester.pump();
    });
  });
}

class _Counter extends EasyFormGenericField<int> {
  const _Counter({required super.controller, super.onChange});

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: () => value = (value ?? 0) + 1,
        child: Text('count=$value'),
      );
}

class _Bare extends EasyFormGenericField<int> {
  const _Bare({required super.controller});
}
