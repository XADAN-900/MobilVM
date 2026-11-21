import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backend.dart';
import '../models.dart';
import '../state.dart';

/// Mimari rengiyle sistem rozeti (98, XP, DOS...).
class OsBadge extends StatelessWidget {
  const OsBadge({super.key, required this.arch, required this.label, this.size = 54});
  final String arch;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final g = archGradient(arch);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: LinearGradient(colors: g, begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [BoxShadow(color: g[1].withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 6))],
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * (label.length > 2 ? 0.27 : 0.36),
          letterSpacing: -0.3,
        ),
      ),
    );
  }
}

class InfoChip extends StatelessWidget {
  const InfoChip(this.text, {super.key, this.color, this.icon});
  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: c), const SizedBox(width: 4)],
        Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c)),
      ]),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.icon, required this.children});
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(icon, size: 20, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

Future<bool> confirm(BuildContext context, String title, String body, {String? ok, bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('Vazgeç', 'Cancel'))),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok ?? t('Tamam', 'OK')),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// QEMU günlüğünü canlı gösteren alt sayfa.
Future<void> showLogSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _LogSheet(),
  );
}

class _LogSheet extends StatefulWidget {
  const _LogSheet();

  @override
  State<_LogSheet> createState() => _LogSheetState();
}

class _LogSheetState extends State<_LogSheet> {
  String _log = '';
  Timer? _timer;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _load());
  }

  Future<void> _load() async {
    final l = await Backend.call<String>('log') ?? '';
    if (!mounted || l == _log) return;
    final atEnd = !_scroll.hasClients || _scroll.position.pixels >= _scroll.position.maxScrollExtent - 40;
    setState(() => _log = l);
    if (atEnd) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Text(t('QEMU günlüğü', 'QEMU log'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const Spacer(),
            IconButton(
              tooltip: t('Kopyala', 'Copy'),
              icon: const Icon(Icons.copy_rounded),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _log));
                toast(context, t('Kopyalandı', 'Copied'));
              },
            ),
          ]),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(14)),
            child: SingleChildScrollView(
              controller: _scroll,
              child: SelectableText(
                _log.isEmpty ? t('(henüz bir şey yok)', '(nothing yet)') : _log,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: Color(0xFFB8F7C8), height: 1.35),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// İçe aktarma (kopyalama) ilerleme şeridi.
class ImportBanner extends StatelessWidget {
  const ImportBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        if (app.importName == null) return const SizedBox.shrink();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${t('Kopyalanıyor', 'Copying')}: ${app.importName}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: app.importProgress <= 0 ? null : app.importProgress),
            ]),
          ),
        );
      },
    );
  }
}
