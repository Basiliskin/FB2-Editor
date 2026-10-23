// PROTOTYPE - THROWAWAY. Shared pieces of the "Library shelf" design language.
import 'package:flutter/material.dart';
import 'package:quill_fb2/services/app.service.dart';

/// New UI strings: (en, ru), chosen by the current language setting.
String tr(AppService s, String en, String ru) =>
    s.getSettings()['language'] == 'ru' ? ru : en;

class ModernPage extends StatelessWidget {
  final Widget child;
  final double max;
  const ModernPage({super.key, required this.child, this.max = 760});
  @override
  Widget build(BuildContext context) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: max), child: child));
}

class ModernGroup extends StatelessWidget {
  final String title;
  final IconData? icon;
  final List<Widget> children;
  const ModernGroup(this.title, this.children, {super.key, this.icon});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: t.colorScheme.primary),
              const SizedBox(width: 8)
            ],
            Text(title,
                style: t.textTheme.titleSmall?.copyWith(
                    color: t.colorScheme.primary, fontWeight: FontWeight.w700)),
          ]),
        ),
        Card(
            margin: EdgeInsets.zero,
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children))),
      ]),
    );
  }
}

AppBar modernAppBar(BuildContext context,
    {required Widget title, List<Widget>? actions, PreferredSizeWidget? bottom, Widget? leading}) {
  final c = Theme.of(context).colorScheme;
  return AppBar(
      backgroundColor: c.surface,
      foregroundColor: c.onSurface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      leading: leading,
      title: title,
      actions: [...?actions, const SizedBox(width: 8)],
      bottom: bottom);
}
