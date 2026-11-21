import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../state.dart';
import '../widgets/common.dart';
import '../widgets/logo.dart';
import '../backend.dart';
import 'details_screen.dart';
import 'display_screen.dart';
import 'editor_screen.dart';
import 'wizard_screen.dart';
import 'images_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    // Ekran kapalıyken VM hata ile kapanırsa haber ver
    _sub = app.events.listen((e) {
      if (e['type'] != 'vm' || e['running'] != false || app.displayOpen || !mounted) return;
      final code = (e['exitCode'] as num?)?.toInt() ?? 0;
      if (code == 0) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(t('Sanal makine beklenmedik şekilde kapandı (kod {0})', 'The VM stopped unexpectedly (code {0})', [code])),
        action: SnackBarAction(label: t('Günlük', 'Log'), onPressed: () => showLogSheet(context)),
      ));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final running = app.runningVm;
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => openWizard(context),
            icon: const Icon(Icons.add_rounded),
            label: Text(t('Yeni VM', 'New VM')),
          ),
          body: SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  toolbarHeight: 68,
                  titleSpacing: 20,
                  title: const StrataWordmark(size: 24),
                  actions: [
                    IconButton(
                      tooltip: t('İmaj kütüphanesi', 'Image library'),
                      icon: const Icon(Icons.album_outlined),
                      onPressed: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const ImagesScreen())),
                    ),
                    IconButton(
                      tooltip: t('Ayarlar', 'Settings'),
                      icon: const Icon(Icons.tune_rounded),
                      onPressed: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                  sliver: SliverList.list(children: [
                    if (!app.qemuOk || app.device['runtime'] != true) ...[
                      const _EngineWarning(),
                      const SizedBox(height: 12),
                    ],
                    if (running != null) ...[
                      _RunningCard(vm: running),
                      const SizedBox(height: 16),
                    ],
                    _DeviceStrip(),
                    const SizedBox(height: 18),
                    if (app.vms.isEmpty)
                      const _EmptyState()
                    else ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 10),
                        child: Text(
                          '${t('Sanal makinelerim', 'My machines')} · ${app.vms.length}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      for (final vm in app.vms) ...[
                        _VmCard(vm: vm),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ]),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Future<void> openEditor(BuildContext context, [VmConfig? vm]) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => EditorScreen(vm: vm)));

Future<void> openWizard(BuildContext context) async {
  final vm = await Navigator.push<VmConfig>(context, MaterialPageRoute(builder: (_) => const WizardScreen()));
  if (vm == null || !context.mounted) return;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => DetailsScreen(vmId: vm.id)));
}

void openDetails(BuildContext context, VmConfig vm) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => DetailsScreen(vmId: vm.id)));

Future<void> startVm(BuildContext context, VmConfig vm) async {
  if (app.runningId == vm.id) {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => DisplayScreen(vm: vm)));
    return;
  }
  if (app.runningId != null) {
    toast(context, t('Aynı anda tek VM çalışabilir. Önce çalışanı kapat.',
        'Only one VM can run at a time. Stop the running one first.'));
    return;
  }
  if (!vm.hasMedia) {
    toast(context, t('Önce bir ISO, disk ya da disket ekle.', 'Add an ISO, disk or floppy first.'));
    await openEditor(context, vm);
    return;
  }
  final problem = vm.bootProblem;
  if (problem != null) {
    toast(context, problem);
    await openEditor(context, vm);
    return;
  }
  if (!app.qemuOk || !app.availableArchs.contains(vm.arch)) {
    toast(context, t('QEMU motoru bu APK\'da yok.', 'The QEMU engine is missing from this APK.'));
    return;
  }
  try {
    await app.start(vm.id);
  } catch (e) {
    if (context.mounted) toast(context, '${t('Başlatılamadı', 'Could not start')}: $e');
    return;
  }
  if (context.mounted) {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => DisplayScreen(vm: vm)));
  }
}

class _EngineWarning extends StatelessWidget {
  const _EngineWarning();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              t('QEMU motoru eksik. APK, QEMU indirme adımı olmadan derlenmiş.',
                  'The QEMU engine is missing. The APK was built without the QEMU download step.'),
              style: TextStyle(color: cs.onErrorContainer),
            ),
          ),
        ]),
      ),
    );
  }
}

class _DeviceStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget stat(IconData i, String v, String l) => Expanded(
          child: Column(children: [
            Icon(i, size: 20, color: cs.primary),
            const SizedBox(height: 6),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            Text(l, style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
          ]),
        );
    final free = (app.device['freeMb'] as num?)?.toInt() ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(children: [
          stat(Icons.memory_rounded, fmtMb(app.totalRamMb), t('Cihaz RAM', 'Device RAM')),
          stat(Icons.developer_board_rounded, '${app.cores}', t('Çekirdek', 'Cores')),
          stat(Icons.sd_storage_rounded, fmtMb(free), t('Boş alan', 'Free space')),
        ]),
      ),
    );
  }
}

class _RunningCard extends StatelessWidget {
  const _RunningCard({required this.vm});
  final VmConfig vm;

  @override
  Widget build(BuildContext context) {
    final g = archGradient(vm.arch);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(colors: [g[1], const Color(0xFF312E81)]),
      ),
      padding: const EdgeInsets.all(18),
      child: Row(children: [
        Container(
          width: 12,
          height: 12,
          decoration: const BoxDecoration(color: Color(0xFF4ADE80), shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('Çalışıyor', 'Running'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Text(vm.name,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ]),
        ),
        IconButton(
          tooltip: t('Kapat', 'Shut down'),
          color: Colors.white,
          icon: const Icon(Icons.power_settings_new_rounded),
          onPressed: () async {
            if (await confirm(context, t('VM kapatılsın mı?', 'Shut down the VM?'),
                t('Kaydedilmemiş veriler kaybolabilir.', 'Unsaved data may be lost.'),
                ok: t('Kapat', 'Shut down'), danger: true)) {
              app.stop();
            }
          },
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
          onPressed: () => startVm(context, vm),
          icon: const Icon(Icons.desktop_windows_rounded, size: 18),
          label: Text(t('Ekran', 'Screen')),
        ),
      ]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 30),
      child: Column(children: [
        const StrataLogo(size: 96),
        const SizedBox(height: 22),
        Text(t('Henüz sanal makine yok', 'No virtual machines yet'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          t('DOS\'tan Windows XP\'ye, Alpine\'den Debian\'a.\n16, 32 ve 64-bit sistemleri telefonunda çalıştır.',
              'From DOS to Windows XP, Alpine to Debian.\nRun 16, 32 and 64-bit systems on your phone.'),
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: () => openWizard(context),
          icon: const Icon(Icons.add_rounded),
          label: Text(t('İlk VM\'ini oluştur', 'Create your first VM')),
        ),
      ]),
    );
  }
}

class _VmCard extends StatelessWidget {
  const _VmCard({required this.vm});
  final VmConfig vm;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final running = app.runningId == vm.id;
    final media = vm.isoPath.isNotEmpty
        ? baseName(vm.isoPath)
        : vm.diskPath.isNotEmpty
            ? baseName(vm.diskPath)
            : vm.floppyPath.isNotEmpty
                ? baseName(vm.floppyPath)
                : t('Medya yok', 'No media');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openDetails(context, vm),
        onLongPress: () => _menu(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            OsBadge(arch: vm.arch, label: vm.os.badge),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(vm.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if (running) InfoChip(t('çalışıyor', 'running'), color: const Color(0xFF4ADE80)),
                  if (!running && vm.savedState) InfoChip(t('kayıtlı', 'saved'), color: const Color(0xFFFBBF24)),
                  InfoChip(vm.archLabel, color: archColor(vm.arch)),
                  InfoChip(fmtMb(vm.ramMb), icon: Icons.memory_rounded),
                  InfoChip('${vm.cpus} CPU'),
                ]),
                const SizedBox(height: 6),
                Text(media,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ]),
            ),
            const SizedBox(width: 8),
            running
                ? FilledButton.tonal(
                    onPressed: () => startVm(context, vm),
                    child: const Icon(Icons.desktop_windows_rounded),
                  )
                : IconButton.filled(
                    iconSize: 28,
                    onPressed: () => startVm(context, vm),
                    icon: const Icon(Icons.play_arrow_rounded),
                  ),
          ]),
        ),
      ),
    );
  }

  void _menu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      // İçerik uzun olsa da ekrana sığsın, gerekirse kaydırılsın; hiçbir şey altta kalmasın
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: MediaQuery.of(c).padding.bottom + 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: OsBadge(arch: vm.arch, label: vm.os.badge, size: 40),
            title: Text(vm.name, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${vm.archLabel} · ${fmtMb(vm.ramMb)} · ${vm.cpus} CPU'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.play_arrow_rounded),
            title: Text(app.runningId == vm.id ? t('Ekrana dön', 'Open screen') : t('Başlat', 'Start')),
            onTap: () {
              Navigator.pop(c);
              startVm(context, vm);
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: Text(t('Ayrıntılar ve anlık görüntüler', 'Details & snapshots')),
            onTap: () {
              Navigator.pop(c);
              openDetails(context, vm);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_rounded),
            title: Text(t('Ayarlar', 'Settings')),
            onTap: () {
              Navigator.pop(c);
              openEditor(context, vm);
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy_all_rounded),
            title: Text(t('Kopyasını oluştur', 'Duplicate')),
            onTap: () async {
              Navigator.pop(c);
              final messenger = ScaffoldMessenger.of(context);
              messenger.showSnackBar(SnackBar(content: Text(t('Kopyalanıyor…', 'Cloning…'))));
              final copy = vm.copy()
                ..id = ''
                ..createdAt = 0
                ..lastRunAt = 0
                ..savedState = false
                ..name = '${vm.name} (${t('kopya', 'copy')})';
              try {
                // Disk paylaşılmasın: VirtualBox'taki gibi tam kopya
                if (vm.diskPath.isNotEmpty) {
                  copy.diskPath = await Backend.call<String>('cloneDisk', {'path': vm.diskPath, 'name': copy.name}) ?? '';
                }
                await app.save(copy);
                messenger.showSnackBar(SnackBar(content: Text(t('Kopya oluşturuldu', 'Clone created'))));
              } catch (e) {
                messenger.showSnackBar(SnackBar(content: Text('$e')));
              }
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: Theme.of(c).colorScheme.error),
            title: Text(t('Sil', 'Delete'), style: TextStyle(color: Theme.of(c).colorScheme.error)),
            onTap: () {
              Navigator.pop(c);
              if (app.runningId == vm.id) {
                toast(context, t('Çalışan VM silinemez. Önce kapat.', 'A running VM can\'t be deleted. Stop it first.'));
                return;
              }
              _delete(context);
            },
          ),
          const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    var files = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(t('"{0}" silinsin mi?', 'Delete "{0}"?', [vm.name])),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(t('VM ayarları silinir. ISO dosyaları kütüphanede kalır.',
                'The VM settings are removed. ISO files stay in the library.')),
            if (vm.diskPath.isNotEmpty)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: files,
                onChanged: (v) => set(() => files = v ?? false),
                title: Text(t('Sanal diski de sil', 'Also delete the virtual disk')),
                subtitle: Text(baseName(vm.diskPath)),
              ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('Vazgeç', 'Cancel'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
              onPressed: () => Navigator.pop(c, true),
              child: Text(t('Sil', 'Delete')),
            ),
          ],
        ),
      ),
    );
    if (ok == true) await app.delete(vm.id, deleteFiles: files);
  }
}
