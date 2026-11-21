import 'package:flutter/material.dart';

import '../backend.dart';
import '../models.dart';
import '../state.dart';
import 'common.dart';

/// Kütüphanedeki dosyalar için algılama sonucu önbelleği (her ISO bir kez okunur).
final Map<String, Future<OsDetection?>> _detectCache = {};

Future<OsDetection?> cachedDetect(String path) => _detectCache.putIfAbsent(path, () => detectOsFromFile(path));

const _phone = '__phone__';
final _copySuffix = RegExp(r'^(.*) \((\d+)\)(\.[^.]*)?$');

/// Ortam seçer: önce kütüphanedeki uygun dosyalar, istenirse telefondan yeni dosya.
/// [kind]: 'cd' | 'floppy' | 'disk'. [vmId]: seçimi yapan VM (disk paylaşım uyarısı için).
Future<String?> chooseMedia(BuildContext context, String kind, {String? vmId}) async {
  final files = await Backend.callList('listImages');
  final list = files.where((f) {
    final c = classifyMedia(f['path'] as String);
    return c == kind || (c == null && kind != 'floppy');
  }).toList();
  if (!context.mounted) return null;

  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (c) => _LibrarySheet(kind: kind, files: list, vmId: vmId),
  );
  if (choice == null || !context.mounted) return null;

  String? path = choice == _phone ? await importFromPhone(context) : choice;
  if (path == null || !context.mounted) return null;
  if (classifyMedia(path) == 'disk' || kind == 'disk') path = await _checkSharedDisk(context, path, vmId);
  return path;
}

/// Telefondan dosya kopyalar. Aynı dosyanın eski bir sürümü kütüphanede varsa yerine koymayı önerir.
Future<String?> importFromPhone(BuildContext context) async {
  String? p;
  try {
    p = await app.pickFile();
  } catch (e) {
    if (context.mounted) toast(context, '${t('Dosya alınamadı', 'Could not import file')}: $e');
    return null;
  }
  if (p == null || !context.mounted) return p;

  final name = baseName(p);
  final m = _copySuffix.firstMatch(name);
  // Diskler hiçbir zaman otomatik değiştirilmez (içlerinde VM verisi var)
  if (m == null || classifyMedia(p) == 'disk') return p;
  final stem = m.group(1)!;
  final ext = m.group(3) ?? '';
  final sib = RegExp('^${RegExp.escape(stem)}( \\(\\d+\\))?${RegExp.escape(ext)}\$');
  final files = await Backend.callList('listImages');
  final older = files.where((f) => f['path'] != p && sib.hasMatch(f['name'] as String)).toList();
  if (older.isEmpty || !context.mounted) return p;

  final replace = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(t('Yeni sürüm mü?', 'A new version?')),
      content: Text(t(
          '"{0}" kütüphanede zaten var. Eski sürümün yerine koyayım mı? Onu kullanan VM\'ler yeni sürümü kullanır.',
          '"{0}" is already in the library. Replace the old version? VMs that use it will use the new version.',
          ['$stem$ext'])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('Ayrı tut', 'Keep both'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t('Eskisinin yerine koy', 'Replace the old one'))),
      ],
    ),
  );
  if (replace != true) return p;
  try {
    final target = await Backend.call<String>('replaceImage', {'path': p});
    _detectCache.clear();
    await app.refresh();
    if (context.mounted) toast(context, t('Eski sürüm değiştirildi', 'Old version replaced'));
    return target ?? p;
  } catch (e) {
    if (context.mounted) {
      toast(
          context,
          '$e'.contains('IN_USE_RUNNING')
              ? t('Çalışan VM bu dosyayı kullanıyor; önce VM\'i kapat.', 'A running VM uses this file; stop the VM first.')
              : '$e');
    }
    return p;
  }
}

/// Başka bir VM'in diski seçildiyse: kopyasını oluştur / yine de kullan / vazgeç.
Future<String?> _checkSharedDisk(BuildContext context, String path, String? vmId) async {
  final users = app.vms.where((v) => v.diskPath == path && v.id != vmId).toList();
  if (users.isEmpty) return path;
  final action = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(t('Bu disk kullanılıyor', 'This disk is in use')),
      content: Text(t('"{0}" bu diski kullanıyor. İki VM aynı diske yazarsa disk bozulabilir.',
          '"{0}" uses this disk. If two VMs write to the same disk, it can get corrupted.', [users.first.name])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(t('Vazgeç', 'Cancel'))),
        TextButton(onPressed: () => Navigator.pop(c, 'use'), child: Text(t('Yine de kullan', 'Use anyway'))),
        FilledButton(onPressed: () => Navigator.pop(c, 'copy'), child: Text(t('Kopyasını oluştur', 'Create a copy'))),
      ],
    ),
  );
  if (action == 'use') return path;
  if (action != 'copy' || !context.mounted) return null;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(children: [
        const CircularProgressIndicator(),
        const SizedBox(width: 20),
        Expanded(child: Text(t('Disk kopyalanıyor…', 'Copying disk…'))),
      ]),
    ),
  );
  try {
    final stem = baseName(path).replaceAll(RegExp(r'\.[^.]+$'), '');
    final copy = await Backend.call<String>('cloneDisk', {'path': path, 'name': '$stem-copy'});
    if (context.mounted) Navigator.pop(context);
    return copy;
  } catch (e) {
    if (context.mounted) {
      Navigator.pop(context);
      toast(context, '$e');
    }
    return null;
  }
}

class _LibrarySheet extends StatelessWidget {
  const _LibrarySheet({required this.kind, required this.files, this.vmId});
  final String kind;
  final List<Map<String, dynamic>> files;
  final String? vmId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = switch (kind) {
      'floppy' => t('Disket imajı seç', 'Choose a floppy image'),
      'disk' => t('Sabit disk seç', 'Choose a hard disk'),
      _ => t('CD / DVD imajı seç', 'Choose a CD / DVD image'),
    };
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Card(
            color: cs.primaryContainer,
            child: ListTile(
              leading: Icon(Icons.phone_android_rounded, color: cs.onPrimaryContainer),
              title: Text(t('Telefondan yeni dosya ekle', 'Add a new file from the phone'),
                  style: TextStyle(fontWeight: FontWeight.w700, color: cs.onPrimaryContainer)),
              subtitle: Text(t('Dosyayı telefondan kopyalar', 'Copies the file from the phone'),
                  style: TextStyle(color: cs.onPrimaryContainer.withOpacity(0.8))),
              onTap: () => Navigator.pop(context, _phone),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 20, 6),
          child: Row(children: [
            Icon(Icons.album_outlined, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Text('${t('İmaj kütüphanesi', 'Image library')} · ${files.length}',
                style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
          ]),
        ),
        Flexible(
          child: files.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  child: Text(t('Kütüphanede uygun dosya yok', 'No matching files in the library'),
                      style: TextStyle(color: cs.onSurfaceVariant)),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.fromLTRB(12, 0, 12, MediaQuery.of(context).padding.bottom + 16),
                  itemCount: files.length,
                  itemBuilder: (_, i) => _FileTile(file: files[i], kind: kind, vmId: vmId),
                ),
        ),
      ]),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({required this.file, required this.kind, this.vmId});
  final Map<String, dynamic> file;
  final String kind;
  final String? vmId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final path = file['path'] as String;
    final users = app.vms.where((v) => v.isoPath == path || v.diskPath == path || v.floppyPath == path).toList();
    final date = DateTime.fromMillisecondsSinceEpoch((file['modified'] as num).toInt());
    String two(int x) => x.toString().padLeft(2, '0');
    final icon = switch (kind) {
      'floppy' => Icons.sd_card_rounded,
      'disk' => Icons.save_rounded,
      _ => Icons.album_rounded,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.pop(context, path),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(children: [
              Icon(icon, color: cs.primary, size: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(file['name'] as String,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text('${fmtBytes((file['size'] as num).toInt())} · ${two(date.day)}.${two(date.month)}.${date.year}',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  if (kind != 'disk')
                    FutureBuilder<OsDetection?>(
                      future: cachedDetect(path),
                      builder: (_, snap) {
                        final d = snap.data;
                        if (d == null) return const SizedBox.shrink();
                        final label = d.custom ? '${d.source} · ${archLabelOf(d.os.arch)}' : d.suggestedName;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(children: [
                            OsBadge(arch: d.os.arch, label: d.os.badge, size: 20),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, color: cs.primary, fontWeight: FontWeight.w600)),
                            ),
                          ]),
                        );
                      },
                    ),
                  if (users.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      for (final u in users.take(3))
                        InfoChip('${t('kullanımda', 'in use')}: ${u.name}',
                            color: u.id == vmId ? cs.primary : Colors.green),
                    ]),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
