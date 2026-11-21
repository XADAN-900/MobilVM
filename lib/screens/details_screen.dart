import 'package:flutter/material.dart';

import '../backend.dart';
import '../models.dart';
import '../state.dart';
import '../widgets/common.dart';
import 'home_screen.dart';

/// VirtualBox'taki sağ panel gibi: VM özeti, anlık görüntüler, paylaşılan klasör.
class DetailsScreen extends StatefulWidget {
  const DetailsScreen({super.key, required this.vmId});
  final String vmId;

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  List<Map<String, dynamic>> _snaps = [];
  String? _snapError;
  bool _snapLoading = false;
  List<Map<String, dynamic>> _shared = [];
  bool _busy = false;

  VmConfig? get _vm {
    for (final v in app.vms) {
      if (v.id == widget.vmId) return v;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadSnaps();
    _loadShared();
  }

  Future<void> _loadSnaps() async {
    final vm = _vm;
    if (vm == null) return;
    if (!vm.snapshotCapable) {
      setState(() {
        _snaps = [];
        _snapError = 'QCOW2';
      });
      return;
    }
    setState(() => _snapLoading = true);
    try {
      final l = await Backend.callList('snapshotList', {'id': vm.id});
      if (mounted) {
        setState(() {
          _snaps = l.where((s) => s['auto'] != true).toList();
          _snapError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _snapError = '$e');
    } finally {
      if (mounted) setState(() => _snapLoading = false);
    }
  }

  Future<void> _loadShared() async {
    final vm = _vm;
    if (vm == null || !vm.sharedFolder) return;
    final l = await Backend.callList('sharedList', {'id': vm.id});
    if (mounted) setState(() => _shared = l);
  }

  Future<void> _snapOp(String op, String name) async {
    setState(() => _busy = true);
    try {
      await Backend.call(op, {'id': widget.vmId, 'name': name});
      if (mounted) {
        toast(context, switch (op) {
          'snapshotCreate' => t('Anlık görüntü alındı', 'Snapshot taken'),
          'snapshotRestore' => t('Geri yüklendi', 'Restored'),
          _ => t('Silindi', 'Deleted'),
        });
      }
      await app.refresh();
    } catch (e) {
      if (mounted) toast(context, '${t('Hata', 'Error')}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
      await _loadSnaps();
    }
  }

  Future<void> _takeSnapshot() async {
    final ctl = TextEditingController(text: 'snap-${DateTime.now().toString().substring(0, 16).replaceAll(RegExp(r'[^0-9]'), '')}');
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t('Anlık görüntü al', 'Take snapshot')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: ctl, autofocus: true, decoration: InputDecoration(labelText: t('Ad', 'Name'))),
          const SizedBox(height: 10),
          Text(
            app.runningId == widget.vmId
                ? t('VM çalışıyor: bellek dahil tüm durum kaydedilir, birkaç saniye donabilir.',
                    'VM is running: the full state including memory is saved; it may freeze for a few seconds.')
                : t('Diskin şu anki hali kaydedilir.', 'The current state of the disk is saved.'),
            style: TextStyle(fontSize: 12.5, color: Theme.of(c).colorScheme.onSurfaceVariant),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(t('Vazgeç', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: Text(t('Al', 'Take'))),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) await _snapOp('snapshotCreate', name);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final vm = _vm;
        if (vm == null) return const Scaffold(body: SizedBox.shrink());
        final cs = Theme.of(context).colorScheme;
        final running = app.runningId == vm.id;
        final os = vm.os;
        return Scaffold(
          appBar: AppBar(
            title: Text(vm.name, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                tooltip: t('Ayarlar', 'Settings'),
                icon: const Icon(Icons.settings_rounded),
                onPressed: () => openEditor(context, vm),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              if (_busy) const LinearProgressIndicator(),
              // ---------------------------------------------------- başlık
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(children: [
                    Row(children: [
                      OsBadge(arch: vm.arch, label: os.badge, size: 64),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(os.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          Row(children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: running
                                    ? const Color(0xFF4ADE80)
                                    : vm.savedState
                                        ? const Color(0xFFFBBF24)
                                        : cs.outline,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(running
                                ? t('Çalışıyor', 'Running')
                                : vm.savedState
                                    ? t('Durum kaydedildi', 'Saved state')
                                    : t('Kapalı', 'Powered off')),
                          ]),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                          onPressed: _busy ? null : () => startVm(context, vm),
                          icon: Icon(running ? Icons.desktop_windows_rounded : Icons.play_arrow_rounded),
                          label: Text(running
                              ? t('Ekranı aç', 'Open screen')
                              : vm.savedState
                                  ? t('Devam ettir', 'Resume')
                                  : t('Başlat', 'Start')),
                        ),
                      ),
                      if (vm.savedState && !running) ...[
                        const SizedBox(width: 10),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                          onPressed: () async {
                            if (await confirm(context, t('Kayıtlı durum silinsin mi?', 'Discard saved state?'),
                                t('VM bir sonraki açılışta baştan başlar.', 'The VM will cold boot next time.'),
                                ok: t('Sil', 'Discard'))) {
                              await Backend.call('discardState', {'id': vm.id});
                              await app.refresh();
                            }
                          },
                          child: Text(t('Durumu at', 'Discard')),
                        ),
                      ],
                    ]),
                  ]),
                ),
              ),
              const SizedBox(height: 12),

              // ---------------------------------------------------- özet
              _info(t('Sistem', 'System'), Icons.memory_rounded, [
                (t('Mimari', 'Architecture'), vm.archLabel),
                ('RAM', fmtMb(vm.ramMb)),
                (t('İşlemci', 'CPU'), '${vm.cpus} × ${vm.cpuModel.isEmpty ? t('otomatik', 'auto') : vm.cpuModel}'),
                (t('Anakart', 'Machine'), isX86Arch(vm.arch) ? vm.machine : archMachineLabel(vm.arch)),
              ]),
              const SizedBox(height: 12),
              _info(t('Ekran ve giriş', 'Display & input'), Icons.monitor_rounded, [
                (t('Ekran kartı', 'Graphics'), isX86Arch(vm.arch) ? vm.vga : (vm.arch == 'ppc' || vm.arch == 'ppc64' ? 'std' : 'virtio-gpu')),
                (t('Fare', 'Mouse'), vm.tablet || !isX86Arch(vm.arch) ? t('USB tablet', 'USB tablet') : 'PS/2'),
                (t('Klavye', 'Keyboard'), vm.keyboard),
              ]),
              const SizedBox(height: 12),
              _info(t('Depolama', 'Storage'), Icons.storage_rounded, [
                ('CD / ISO', vm.isoPath.isEmpty ? '—' : baseName(vm.isoPath)),
                (t('Disk', 'Disk'), vm.diskPath.isEmpty ? '—' : baseName(vm.diskPath)),
                (t('Disket', 'Floppy'), vm.floppyPath.isEmpty ? '—' : baseName(vm.floppyPath)),
                (t('Önyükleme', 'Boot'), switch (vm.boot) { 'disk' => 'Disk', 'floppy' => t('Disket', 'Floppy'), _ => 'CD' }),
              ]),
              const SizedBox(height: 12),
              _info(t('Ağ', 'Network'), Icons.lan_rounded, [
                (t('Bağlantı', 'Attached to'), vm.net ? 'NAT' : t('Kapalı', 'Off')),
                if (vm.net) (t('Kart', 'Adapter'), vm.nic),
                if (vm.net && vm.portForwards.isNotEmpty) (t('Portlar', 'Ports'), vm.portForwards),
              ]),
              const SizedBox(height: 12),

              // ---------------------------------------------------- anlık görüntüler
              SectionCard(title: t('Anlık görüntüler', 'Snapshots'), icon: Icons.history_rounded, children: [
                if (_snapError == 'QCOW2')
                  Text(
                    t('Anlık görüntü için sanal diskin qcow2 olması gerekir. Sihirbazla oluşturulan diskler qcow2\'dir.',
                        'Snapshots require a qcow2 virtual disk. Disks created by the wizard are qcow2.'),
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  )
                else ...[
                  if (_snapLoading) const LinearProgressIndicator(),
                  if (_snapError != null)
                    Text(_snapError!, style: TextStyle(color: cs.error, fontSize: 12.5)),
                  if (_snaps.isEmpty && !_snapLoading && _snapError == null)
                    Text(t('Henüz anlık görüntü yok.', 'No snapshots yet.'),
                        style: TextStyle(color: cs.onSurfaceVariant)),
                  for (final s in _snaps)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.camera_rounded, color: cs.primary),
                      title: Text(s['name'] as String),
                      subtitle: Text(_fmtDate((s['date'] as num).toInt()) +
                          (((s['vmStateSize'] as num?) ?? 0) > 0 ? ' · ${t('bellek dahil', 'with memory')}' : '')),
                      trailing: PopupMenuButton<String>(
                        onSelected: (a) async {
                          final name = s['name'] as String;
                          if (a == 'restore') {
                            if (await confirm(
                                context,
                                t('Geri yüklensin mi?', 'Restore?'),
                                t('Mevcut durum bu anlık görüntüyle değiştirilir.',
                                    'The current state will be replaced by this snapshot.'),
                                ok: t('Geri yükle', 'Restore'))) {
                              await _snapOp('snapshotRestore', name);
                            }
                          } else {
                            if (await confirm(context, t('Silinsin mi?', 'Delete?'), name,
                                ok: t('Sil', 'Delete'), danger: true)) {
                              await _snapOp('snapshotDelete', name);
                            }
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'restore', child: Text(t('Geri yükle', 'Restore'))),
                          PopupMenuItem(value: 'delete', child: Text(t('Sil', 'Delete'))),
                        ],
                      ),
                    ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: _busy ? null : _takeSnapshot,
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: Text(t('Anlık görüntü al', 'Take snapshot')),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 12),

              // ---------------------------------------------------- paylaşılan klasör
              SectionCard(title: t('Paylaşılan klasör', 'Shared folder'), icon: Icons.folder_shared_rounded, children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: vm.sharedFolder,
                  onChanged: running
                      ? null
                      : (x) async {
                          await app.save(vm.copy()..sharedFolder = x);
                          await _loadShared();
                        },
                  title: Text(t('Telefondan VM\'e dosya aktar', 'Transfer files from phone to VM')),
                  subtitle: Text(vm.sharedWritable
                      ? t('Eklediğin dosyalar VM\'de ayrı bir sürücü (FAT) olarak görünür. En fazla ~500 MB. VM\'in kaydettikleri buraya gelir.',
                          'Files you add appear as a separate FAT drive in the VM. Up to ~500 MB. Files the VM saves show up here.')
                      : t(
                      'Eklediğin dosyalar VM\'de ayrı bir sürücü (FAT) olarak görünür. En fazla ~500 MB. VM\'in yazdıkları kaybolur.',
                      'Files you add appear as a separate FAT drive in the VM. Up to ~500 MB. Changes made by the VM are discarded.')),
                ),
                if (vm.sharedFolder)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: vm.sharedWritable,
                    onChanged: running ? null : (x) => app.save(vm.copy()..sharedWritable = x),
                    title: Text(t('VM klasöre yazabilsin', 'Let the VM write to the folder')),
                  ),
                if (vm.sharedFolder) ...[
                  for (final f in _shared)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.insert_drive_file_outlined),
                      title: Text(f['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(fmtBytes((f['size'] as num).toInt())),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          tooltip: t('İndirilenler\'e aktar', 'Export to Downloads'),
                          icon: const Icon(Icons.download_rounded),
                          onPressed: () async {
                            try {
                              final p = await Backend.call<String>('sharedExport', {'id': vm.id, 'path': f['path']});
                              if (context.mounted) toast(context, '${t('Kaydedildi', 'Saved')}: $p');
                            } catch (e) {
                              if (context.mounted) toast(context, '$e');
                            }
                          },
                        ),
                        IconButton(
                          tooltip: t('Kaldır', 'Remove'),
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () async {
                            await Backend.call('sharedDelete', {'id': vm.id, 'path': f['path']});
                            await _loadShared();
                          },
                        ),
                      ]),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: () async {
                        try {
                          await app.pickFile(sharedFor: vm.id);
                        } catch (e) {
                          if (context.mounted) toast(context, '$e');
                        }
                        await _loadShared();
                      },
                      icon: const Icon(Icons.upload_file_rounded),
                      label: Text(t('Dosya ekle', 'Add file')),
                    ),
                  ),
                  if (running)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(t('Yeni dosyalar VM yeniden başlatılınca görünür.', 'New files appear after the VM restarts.'),
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ),
                ],
              ]),
            ],
          ),
        );
      },
    );
  }

  Widget _info(String title, IconData icon, List<(String, String)> rows) {
    final cs = Theme.of(context).colorScheme;
    return SectionCard(title: title, icon: icon, children: [
      for (final (k, v) in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 110, child: Text(k, style: TextStyle(color: cs.onSurfaceVariant))),
            Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        ),
    ]);
  }

  String _fmtDate(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
  }
}
