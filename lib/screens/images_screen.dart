import 'package:flutter/material.dart';

import '../backend.dart';
import '../models.dart';
import '../state.dart';
import '../widgets/common.dart';
import '../widgets/media_picker.dart';

/// Telefona aktarılmış ISO / disk / disket dosyaları.
class ImagesScreen extends StatefulWidget {
  const ImagesScreen({super.key});

  @override
  State<ImagesScreen> createState() => _ImagesScreenState();
}

class _ImagesScreenState extends State<ImagesScreen> {
  List<Map<String, dynamic>> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final f = await Backend.callList('listImages');
    if (mounted) setState(() {
      _files = f;
      _loading = false;
    });
  }

  IconData _icon(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.iso')) return Icons.album_rounded;
    if (n.endsWith('.ima') || n.endsWith('.flp') || n.endsWith('.vfd')) return Icons.sd_card_rounded;
    return Icons.save_rounded;
  }

  String _kind(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.iso')) return 'ISO';
    if (n.endsWith('.qcow2')) return 'QCOW2';
    if (n.endsWith('.vdi')) return 'VDI';
    if (n.endsWith('.vmdk')) return 'VMDK';
    if (n.endsWith('.vhd') || n.endsWith('.vhdx')) return 'VHD';
    return 'IMG';
  }

  bool _inUse(String path) =>
      app.vms.any((v) => v.uses(path));

  Future<void> _import() async {
    final p = await importFromPhone(context);
    if (p != null && mounted) toast(context, '${t('Eklendi', 'Added')}: ${baseName(p)}');
    await _load();
  }

  /// Hiçbir VM'in kullanmadığı dosyaları siler.
  Future<void> _cleanUnused() async {
    final unused = _files.where((f) => !_inUse(f['path'] as String)).toList();
    if (unused.isEmpty) {
      toast(context, t('Kullanılmayan dosya yok', 'No unused files'));
      return;
    }
    final bytes = unused.fold<int>(0, (s, f) => s + ((f['size'] as num?)?.toInt() ?? 0));
    final ok = await confirm(
      context,
      t('Kullanılmayanları temizle', 'Clean up unused'),
      '${t('{0} dosya silinecek, {1} yer açılacak. Hiçbir VM bu dosyaları kullanmıyor.', '{0} files will be deleted, freeing {1}. No VM uses these files.', [unused.length, fmtBytes(bytes)])}'
      '\n\n${unused.take(8).map((f) => '• ${f['name']}').join('\n')}${unused.length > 8 ? '\n…' : ''}',
      ok: t('Temizle', 'Clean up'),
      danger: true,
    );
    if (!ok) return;
    for (final f in unused) {
      await Backend.call('deleteImage', {'path': f['path']});
    }
    if (mounted) toast(context, t('{0} yer açıldı', '{0} freed', [fmtBytes(bytes)]));
    await _load();
  }

  Future<void> _delete(Map<String, dynamic> f) async {
    final path = f['path'] as String;
    final used = _inUse(path);
    final ok = await confirm(
      context,
      t('Dosya silinsin mi?', 'Delete file?'),
      '${f['name']}\n\n${used ? t('⚠ Bu dosyayı bir VM kullanıyor.', '⚠ A VM uses this file.') : ''}',
      ok: t('Sil', 'Delete'),
      danger: true,
    );
    if (!ok) return;
    await Backend.call('deleteImage', {'path': path});
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = _files.fold<int>(0, (s, f) => s + ((f['size'] as num?)?.toInt() ?? 0));
    final unusedBytes = _files
        .where((f) => !_inUse(f['path'] as String))
        .fold<int>(0, (s, f) => s + ((f['size'] as num?)?.toInt() ?? 0));
    return Scaffold(
      appBar: AppBar(
        title: Text(t('İmaj kütüphanesi', 'Image library')),
        actions: [
          IconButton(
            tooltip: t('Kullanılmayanları temizle', 'Clean up unused'),
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: _files.isEmpty ? null : _cleanUnused,
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _import,
        icon: const Icon(Icons.file_download_outlined),
        label: Text(t('Dosya ekle', 'Add file')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              children: [
                const ImportBanner(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 4, 12),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        '${_files.length} ${t('dosya', 'files')} · ${fmtBytes(total)}',
                        style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (unusedBytes > 0)
                      TextButton.icon(
                        onPressed: _cleanUnused,
                        icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                        label: Text('${t('Temizle', 'Clean up')} · ${fmtBytes(unusedBytes)}'),
                      ),
                  ]),
                ),
                if (_files.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 60),
                    child: Column(children: [
                      Icon(Icons.album_outlined, size: 64, color: cs.onSurfaceVariant),
                      const SizedBox(height: 12),
                      Text(t('Henüz dosya yok', 'No files yet'), style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(
                        t('ISO, IMG, QCOW2, VDI, VMDK, VHD desteklenir', 'ISO, IMG, QCOW2, VDI, VMDK and VHD are supported'),
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ]),
                  ),
                for (final f in _files)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                        leading: Icon(_icon(f['name'] as String), color: cs.primary, size: 30),
                        title: Text(f['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(spacing: 6, children: [
                            InfoChip(_kind(f['name'] as String), color: cs.primary),
                            InfoChip(fmtBytes((f['size'] as num).toInt())),
                            if (_inUse(f['path'] as String)) InfoChip(t('kullanımda', 'in use'), color: Colors.green),
                            if (classifyMedia(f['path'] as String) != 'disk')
                              FutureBuilder<OsDetection?>(
                                future: cachedDetect(f['path'] as String),
                                builder: (_, snap) => snap.data == null
                                    ? const SizedBox.shrink()
                                    : InfoChip(snap.data!.custom ? snap.data!.source : snap.data!.suggestedName,
                                        color: archColor(snap.data!.os.arch)),
                              ),
                          ]),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => _delete(f),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
