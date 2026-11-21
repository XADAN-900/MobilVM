import 'package:flutter/material.dart';

import '../backend.dart';
import '../models.dart';
import '../state.dart';
import '../widgets/common.dart';
import '../widgets/logo.dart';
import 'editor_screen.dart' show keyboardLayouts;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _qemu = '…';

  @override
  void initState() {
    super.initState();
    Backend.call<String>('qemuVersion').then((v) {
      if (mounted) setState(() => _qemu = v ?? '—');
    }).catchError((_) {
      if (mounted) setState(() => _qemu = '—');
    });
  }

  Widget _seg<T>(String title, String? sub, T value, Map<T, String> opts, ValueChanged<T> onChanged) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        if (sub != null) Text(sub, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<T>(
            showSelectedIcon: false,
            segments: [for (final e in opts.entries) ButtonSegment(value: e.key, label: Text(e.value))],
            selected: {value},
            onSelectionChanged: (s) => onChanged(s.first),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final s = app.settings;
        return Scaffold(
          appBar: AppBar(title: Text(t('Ayarlar', 'Settings'))),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              SectionCard(title: t('Görünüm', 'Appearance'), icon: Icons.palette_outlined, children: [
                _seg<String>(t('Dil', 'Language'), null, s['language'] as String? ?? 'system',
                    {'system': t('Sistem', 'System'), 'tr': 'Türkçe', 'en': 'English'},
                    (v) => app.setSetting('language', v)),
                _seg<String>(t('Tema', 'Theme'), null, s['theme'] as String? ?? 'dark',
                    {'dark': t('Koyu', 'Dark'), 'light': t('Açık', 'Light'), 'system': t('Sistem', 'System')},
                    (v) => app.setSetting('theme', v)),
              ]),
              const SizedBox(height: 12),
              SectionCard(title: t('Ekran ve giriş', 'Display & input'), icon: Icons.monitor_rounded, children: [
                _seg<String>(
                    t('Görüntü ölçekleme', 'Scaling'),
                    t('Keskin: piksel piksel (DOS için güzel)', 'Sharp: pixel-perfect (nice for DOS)'),
                    s['filter'] as String? ?? 'smooth',
                    {'smooth': t('Yumuşak', 'Smooth'), 'sharp': t('Keskin', 'Sharp')},
                    (v) => app.setSetting('filter', v)),
                _seg<String>(
                    t('Varsayılan fare modu', 'Default mouse mode'),
                    t('Touchpad modu PS/2 farelerde (DOS, Win 9x) daha iyi çalışır',
                        'Trackpad mode works better with PS/2 mice (DOS, Win 9x)'),
                    s['mouseMode'] as String? ?? 'touch',
                    {'touch': t('Dokunmatik', 'Touch'), 'trackpad': 'Touchpad'},
                    (v) => app.setSetting('mouseMode', v)),
                DropdownButtonFormField<String>(
                  value: keyboardLayouts.containsKey(s['keyboard']) ? s['keyboard'] as String : 'en-us',
                  isExpanded: true,
                  decoration: InputDecoration(labelText: t('Yeni VM\'ler için klavye düzeni', 'Keyboard layout for new VMs')),
                  items: [
                    for (final e in keyboardLayouts.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) {
                    if (v != null) app.setSetting('keyboard', v);
                  },
                ),
              ]),
              const SizedBox(height: 12),
              SectionCard(title: t('Performans', 'Performance'), icon: Icons.speed_rounded, children: [
                _seg<int>(
                    t('Kod çeviri önbelleği', 'Translation cache'),
                    t('Büyük önbellek = daha hızlı, ama daha çok RAM', 'Bigger cache = faster, but more RAM'),
                    (s['tbSize'] as num?)?.toInt() ?? 256,
                    {128: '128 MB', 256: '256 MB', 512: '512 MB'},
                    (v) => app.setSetting('tbSize', v)),
                Text(
                  t('Telefonlarda x86 donanım sanallaştırması yok; komutlar yazılımla çevrilir. '
                      'DOS, Win 9x/XP ve hafif Linux akıcıdır; ağır sistemler yavaştır.',
                      'Phones have no x86 hardware virtualization; instructions are translated in software. '
                      'DOS, Win 9x/XP and light Linux run smoothly; heavy systems are slow.'),
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant, height: 1.4),
                ),
              ]),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    const StrataWordmark(size: 26),
                    const SizedBox(height: 16),
                    _info(t('Sürüm', 'Version'), '1.0.0'),
                    _info(t('Motor', 'Engine'), _qemu),
                    _info(t('Cihaz', 'Device'), '${app.device['model'] ?? ''} · Android ${app.device['android'] ?? ''}'),
                    _info('RAM / CPU', '${fmtMb(app.totalRamMb)} · ${app.cores} ${t('çekirdek', 'cores')}'),
                    const SizedBox(height: 12),
                    Text(
                      t('QEMU, GNU GPL v2 lisansıyla dağıtılır. Strata VM, QEMU\'yu ayrı bir süreç olarak çalıştırır.',
                          'QEMU is distributed under the GNU GPL v2. Strata VM runs QEMU as a separate process.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: () => showLicensePage(
                        context: context,
                        applicationName: 'Strata VM',
                        applicationVersion: '1.0.0',
                        applicationIcon: const Padding(padding: EdgeInsets.all(12), child: StrataLogo(size: 56)),
                      ),
                      icon: const Icon(Icons.gavel_rounded, size: 18),
                      label: Text(t('Lisanslar', 'Licenses')),
                    ),
                    TextButton.icon(
                      onPressed: () => showLogSheet(context),
                      icon: const Icon(Icons.receipt_long_outlined, size: 18),
                      label: Text(t('Son QEMU günlüğü', 'Last QEMU log')),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _info(String k, String v) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 90, child: Text(k, style: TextStyle(color: cs.onSurfaceVariant))),
        Expanded(child: Text(v, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600))),
      ]),
    );
  }
}
