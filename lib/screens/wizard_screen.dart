import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../backend.dart';
import '../models.dart';
import '../state.dart';
import '../widgets/common.dart';

const ramSteps = [8, 16, 32, 64, 128, 256, 384, 512, 768, 1024, 1536, 2048, 3072, 4096, 6144, 8192, 12288, 16384];
const diskSteps = [64, 128, 256, 512, 1024, 2048, 4096, 8192, 12288, 16384, 20480, 32768, 40960, 65536, 131072, 262144];

int maxRamFor(String arch) {
  final cap = arch == 'x86_16' ? 256 : 16384;
  return math.min(cap, math.max(64, (app.totalRamMb * 0.6).floor()));
}

List<int> ramOptionsFor(String arch, int current) {
  final l = ramSteps.where((s) => s <= maxRamFor(arch)).toList();
  if (!l.contains(current)) {
    l
      ..add(current)
      ..sort();
  }
  return l;
}

/// VirtualBox'taki "Yeni sanal makine" sihirbazı:
/// 1) Ad ve işletim sistemi  2) Donanım  3) Sanal sabit disk  4) Özet
class WizardScreen extends StatefulWidget {
  const WizardScreen({super.key});

  @override
  State<WizardScreen> createState() => _WizardScreenState();
}

enum _DiskMode { create, existing, none }

class _WizardScreenState extends State<WizardScreen> {
  int _step = 0;
  final _name = TextEditingController();
  String _family = 'windows';
  OsType _os = osById('winxp');
  bool _nameTouchedOs = false; // kullanıcı sürümü elle seçtiyse addan tahmin etme
  late VmConfig _vm;
  _DiskMode _diskMode = _DiskMode.create;
  int _diskMb = 10240;
  String _existingDisk = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _vm = _os.create();
    _name.text = '';
    _diskMb = _os.diskMb;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _selectOs(OsType os, {bool fromUser = false}) {
    setState(() {
      if (fromUser) _nameTouchedOs = true;
      _os = os;
      _family = os.family;
      final iso = _vm.isoPath, floppy = _vm.floppyPath;
      _vm = os.create()
        ..isoPath = iso
        ..floppyPath = floppy;
      // Önyükleme: sürümün tercihi, ama yalnızca o ortam seçiliyse
      if (os.boot == 'floppy' && floppy.isEmpty && iso.isNotEmpty) _vm.boot = 'cd';
      if (os.boot == 'cd' && iso.isEmpty && floppy.isNotEmpty) _vm.boot = 'floppy';
      _vm.ramMb = math.min(_vm.ramMb, maxRamFor(_vm.arch));
      _vm.cpus = math.min(_vm.cpus, math.max(1, math.min(app.cores, 8)));
      _diskMb = os.diskMb == 0 ? 1024 : os.diskMb;
      if (_diskMode != _DiskMode.existing) {
        _diskMode = os.diskMb == 0 ? _DiskMode.none : _DiskMode.create;
      }
    });
  }

  void _onNameChanged(String v) {
    if (_nameTouchedOs) return;
    final d = detectOs(v);
    if (d != null && d.id != _os.id) _selectOs(d);
  }

  /// CD, disket veya hazır disk imajı seçer; dosya türü yanlış satıra seçildiyse doğru yere koyar.
  Future<void> _pickMedia(String slot) async {
    try {
      final p = await app.pickFile();
      if (p == null) return;
      final detected = classifyMedia(p);
      final kind = detected ?? slot;
      setState(() => _setMedia(kind, p));
      if (kind != slot && mounted) {
        toast(context, '${baseName(p)} → ${mediaLabel(kind)}');
      }
      final d = detectOs(baseName(p));
      if (d != null && !_nameTouchedOs) {
        _selectOs(d);
        if (_name.text.trim().isEmpty) _name.text = d.name;
        if (mounted) toast(context, '${t('Algılandı', 'Detected')}: ${d.name}');
      }
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  void _setMedia(String kind, String path) {
    switch (kind) {
      case 'floppy':
        _vm.floppyPath = path;
        if (_vm.isoPath.isEmpty || _os.boot == 'floppy') _vm.boot = 'floppy';
        break;
      case 'disk':
        _existingDisk = path;
        _diskMode = _DiskMode.existing;
        if (_vm.isoPath.isEmpty && _vm.floppyPath.isEmpty) _vm.boot = 'disk';
        break;
      default:
        _vm.isoPath = path;
        if (_vm.floppyPath.isEmpty || _os.boot != 'floppy') _vm.boot = 'cd';
    }
  }

  void _clearMedia(String kind) {
    setState(() {
      switch (kind) {
        case 'floppy':
          _vm.floppyPath = '';
          break;
        case 'disk':
          _existingDisk = '';
          _diskMode = _os.diskMb == 0 ? _DiskMode.none : _DiskMode.create;
          break;
        default:
          _vm.isoPath = '';
      }
      _fixBoot();
    });
  }

  /// Önyükleme aygıtı mevcut bir ortamı göstersin.
  void _fixBoot() {
    final hasDisk = _diskMode != _DiskMode.none;
    if (_vm.boot == 'cd' && _vm.isoPath.isEmpty) {
      _vm.boot = _vm.floppyPath.isNotEmpty ? 'floppy' : 'disk';
    } else if (_vm.boot == 'floppy' && _vm.floppyPath.isEmpty) {
      _vm.boot = _vm.isoPath.isNotEmpty ? 'cd' : 'disk';
    } else if (_vm.boot == 'disk' && !hasDisk) {
      _vm.boot = _vm.isoPath.isNotEmpty ? 'cd' : 'floppy';
    }
  }

  Future<void> _pickDisk() async {
    try {
      final p = await app.pickFile();
      if (p != null) {
        setState(() {
          _existingDisk = p;
          if (_vm.isoPath.isEmpty && _vm.floppyPath.isEmpty) _vm.boot = 'disk';
        });
      }
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  bool get _canNext {
    if (_step == 0) return _name.text.trim().isNotEmpty;
    if (_step == 2 && _diskMode == _DiskMode.existing) return _existingDisk.isNotEmpty;
    return true;
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    try {
      _vm.name = _name.text.trim();
      if (_diskMode == _DiskMode.create) {
        final p = await Backend.call<String>('createDisk', {'name': _vm.name, 'sizeMb': _diskMb});
        _vm.diskPath = p ?? '';
      } else if (_diskMode == _DiskMode.existing) {
        _vm.diskPath = _existingDisk;
      } else {
        _vm.diskPath = '';
      }
      _fixBoot();
      final saved = await app.save(_vm);
      if (!mounted) return;
      Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) toast(context, '${t('Oluşturulamadı', 'Could not create')}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = [
      t('Ad ve işletim sistemi', 'Name and operating system'),
      t('Donanım', 'Hardware'),
      t('Sanal sabit disk', 'Virtual hard disk'),
      t('Özet', 'Summary'),
    ];
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(t('Yeni sanal makine', 'New virtual machine'))),
      body: Column(children: [
        // adım göstergesi
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(children: [
            for (var i = 0; i < 4; i++)
              Expanded(
                child: Container(
                  height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i <= _step ? cs.primary : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 4),
          child: Row(children: [
            Text('${_step + 1}/4  ', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800)),
            Expanded(child: Text(titles[_step], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
          ]),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              const ImportBanner(),
              if (_busy) const LinearProgressIndicator(),
              ...switch (_step) {
                0 => _stepOs(),
                1 => _stepHardware(),
                2 => _stepDisk(),
                _ => _stepSummary(),
              },
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(children: [
              if (_step > 0)
                OutlinedButton(
                  onPressed: _busy ? null : () => setState(() => _step--),
                  child: Text(t('Geri', 'Back')),
                ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _busy || !_canNext
                    ? null
                    : () {
                        if (_step < 3) {
                          FocusScope.of(context).unfocus();
                          setState(() => _step++);
                        } else {
                          _finish();
                        }
                      },
                icon: Icon(_step < 3 ? Icons.arrow_forward_rounded : Icons.check_rounded),
                label: Text(_step < 3 ? t('İleri', 'Next') : t('Bitir', 'Finish')),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------- 1
  List<Widget> _stepOs() {
    final cs = Theme.of(context).colorScheme;
    final versions = osOfFamily(_family);
    return [
      SectionCard(title: t('Ad', 'Name'), icon: Icons.badge_outlined, children: [
        TextField(
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: t('ör. Windows XP', 'e.g. Windows XP'),
            helperText: t('Ada göre sistem otomatik seçilir', 'The OS is picked automatically from the name'),
          ),
          onChanged: (v) {
            _onNameChanged(v);
            setState(() {});
          },
        ),
      ]),
      const SizedBox(height: 12),
      SectionCard(title: t('Kurulum ortamı', 'Installation media'), icon: Icons.album_rounded, children: [
        _mediaRow('cd', Icons.album_rounded, t('CD / DVD imajı', 'CD / DVD image'), 'ISO, BIN, IMG', _vm.isoPath),
        _mediaRow('floppy', Icons.sd_card_rounded, t('Disket imajı', 'Floppy image'), 'IMG, IMA, FLP, VFD', _vm.floppyPath),
        _mediaRow('disk', Icons.save_rounded, t('Hazır sabit disk imajı', 'Ready-made hard disk image'),
            'IMG, QCOW2, VDI, VMDK, VHD', _existingDisk),
        const SizedBox(height: 6),
        Text(
          t('Hepsi isteğe bağlı. Dosya türü otomatik tanınır; ISO/dosya adından sistem de algılanır.',
              'All optional. The file type is recognized automatically; the OS is detected from the file name.'),
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        if ([_vm.isoPath, _vm.floppyPath, _existingDisk].where((p) => p.isNotEmpty).length > 1) ...[
          const SizedBox(height: 12),
          Text(t('Önyükleme', 'Boot from'), style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: [
              if (_vm.isoPath.isNotEmpty) const ButtonSegment(value: 'cd', icon: Icon(Icons.album_rounded), label: Text('CD')),
              if (_vm.floppyPath.isNotEmpty)
                ButtonSegment(value: 'floppy', icon: const Icon(Icons.sd_card_rounded), label: Text(t('Disket', 'Floppy'))),
              if (_existingDisk.isNotEmpty)
                const ButtonSegment(value: 'disk', icon: Icon(Icons.save_rounded), label: Text('Disk')),
            ],
            selected: {_vm.boot},
            onSelectionChanged: (x) => setState(() => _vm.boot = x.first),
          ),
        ],
      ]),
      const SizedBox(height: 12),
      SectionCard(title: t('İşletim sistemi', 'Operating system'), icon: Icons.computer_rounded, children: [
        DropdownButtonFormField<String>(
          value: _family,
          isExpanded: true,
          decoration: InputDecoration(labelText: t('Tür', 'Type')),
          items: [
            for (final f in osFamilies)
              DropdownMenuItem(
                value: f.id,
                child: Row(children: [Icon(f.icon, size: 20), const SizedBox(width: 10), Text(f.name)]),
              ),
          ],
          onChanged: (f) {
            if (f == null || f == _family) return;
            _selectOs(osOfFamily(f).first, fromUser: true);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('ver-$_family'),
          value: versions.any((o) => o.id == _os.id) ? _os.id : versions.first.id,
          isExpanded: true,
          decoration: InputDecoration(labelText: t('Sürüm', 'Version')),
          items: [
            for (final o in versions)
              DropdownMenuItem(
                value: o.id,
                child: Row(children: [
                  OsBadge(arch: o.arch, label: o.badge, size: 26),
                  const SizedBox(width: 10),
                  Expanded(child: Text(o.name, overflow: TextOverflow.ellipsis)),
                  Text(archLabelOf(o.arch), style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
                ]),
              ),
          ],
          onChanged: (id) {
            if (id != null) _selectOs(osById(id), fromUser: true);
          },
        ),
        const SizedBox(height: 14),
        _OsPreview(os: _os),
      ]),
    ];
  }

  Widget _mediaRow(String kind, IconData icon, String title, String formats, String path) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(0.35),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Icon(icon, color: path.isEmpty ? cs.onSurfaceVariant : cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                path.isEmpty ? formats : baseName(path),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: path.isEmpty ? cs.onSurfaceVariant : cs.primary),
              ),
            ]),
          ),
          if (path.isNotEmpty)
            IconButton(
              tooltip: t('Kaldır', 'Remove'),
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: () => _clearMedia(kind),
            ),
          TextButton(
            onPressed: _busy ? null : () => _pickMedia(kind),
            child: Text(path.isEmpty ? t('Seç', 'Choose') : t('Değiştir', 'Change')),
          ),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- 2
  List<Widget> _stepHardware() {
    final cs = Theme.of(context).colorScheme;
    final opts = ramOptionsFor(_vm.arch, _vm.ramMb);
    final maxCpu = math.max(1, math.min(app.cores, 8));
    final tooMuch = _vm.ramMb > app.totalRamMb * 0.5;
    return [
      SectionCard(title: t('Bellek (RAM)', 'Memory (RAM)'), icon: Icons.memory_rounded, children: [
        Row(children: [
          Text(fmtMb(_vm.ramMb), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: cs.primary)),
          const Spacer(),
          Text('${t('Önerilen', 'Recommended')}: ${fmtMb(_os.ram)}', style: TextStyle(color: cs.onSurfaceVariant)),
        ]),
        Slider(
          value: opts.indexOf(_vm.ramMb).toDouble(),
          min: 0,
          max: (opts.length - 1).toDouble(),
          divisions: math.max(1, opts.length - 1),
          onChanged: (x) => setState(() => _vm.ramMb = opts[x.round()]),
        ),
        Text(
          tooMuch
              ? t('⚠ Telefon belleğinin yarısından fazlası. Uygulamalar kapanabilir.',
                  '⚠ More than half of the phone\'s memory. Apps may be closed.')
              : '${t('Telefonda', 'Phone has')} ${fmtMb(app.totalRamMb)}',
          style: TextStyle(fontSize: 12.5, color: tooMuch ? cs.error : cs.onSurfaceVariant),
        ),
      ]),
      const SizedBox(height: 12),
      SectionCard(title: t('İşlemci', 'Processor'), icon: Icons.developer_board_rounded, children: [
        Row(children: [
          Text('${_vm.cpus} ${t('çekirdek', 'cores')}',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: cs.primary)),
          const Spacer(),
          Text('${t('Telefonda', 'Phone has')} ${app.cores}', style: TextStyle(color: cs.onSurfaceVariant)),
        ]),
        Slider(
          value: _vm.cpus.clamp(1, maxCpu).toDouble(),
          min: 1,
          max: maxCpu.toDouble(),
          divisions: math.max(1, maxCpu - 1),
          onChanged: maxCpu == 1 ? null : (x) => setState(() => _vm.cpus = x.round()),
        ),
        if (_vm.arch == 'x86_16')
          Text(t('16-bit sistemler tek çekirdek kullanır.', '16-bit systems use a single core.'),
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
      ]),
      if (_os.heavy) ...[
        const SizedBox(height: 12),
        Card(
          color: cs.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(Icons.speed_rounded, color: cs.onTertiaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t('Bu sistem ağırdır. Telefonda x86 emülasyonu yazılımla yapıldığı için yavaş çalışacaktır.',
                      'This OS is heavy. x86 emulation on a phone is done in software, so it will be slow.'),
                  style: TextStyle(color: cs.onTertiaryContainer),
                ),
              ),
            ]),
          ),
        ),
      ],
    ];
  }

  // ---------------------------------------------------------------- 3
  List<Widget> _stepDisk() {
    final cs = Theme.of(context).colorScheme;
    var idx = diskSteps.indexOf(_diskMb);
    if (idx < 0) idx = diskSteps.indexWhere((d) => d >= _diskMb).clamp(0, diskSteps.length - 1).toInt();
    final free = (app.device['freeMb'] as num?)?.toInt();
    Widget radio(_DiskMode m, String title, String sub) => RadioListTile<_DiskMode>(
          contentPadding: EdgeInsets.zero,
          value: m,
          groupValue: _diskMode,
          onChanged: (x) => setState(() => _diskMode = x!),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(sub),
        );
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
          child: Column(children: [
            radio(_DiskMode.create, t('Yeni sanal disk oluştur', 'Create a new virtual disk'),
                t('Önerilen: ${fmtMb(_os.diskMb == 0 ? 1024 : _os.diskMb)} (qcow2)', 'Recommended: ${fmtMb(_os.diskMb == 0 ? 1024 : _os.diskMb)} (qcow2)')),
            radio(_DiskMode.existing, t('Var olan disk dosyasını kullan', 'Use an existing disk file'),
                'IMG, QCOW2, VDI, VMDK, VHD'),
            radio(_DiskMode.none, t('Disk ekleme', 'Do not add a disk'),
                t('Canlı CD / disketten çalışan sistemler için', 'For live CD / floppy systems')),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      if (_diskMode == _DiskMode.create)
        SectionCard(title: t('Disk boyutu', 'Disk size'), icon: Icons.save_rounded, children: [
          Text(fmtMb(diskSteps[idx]), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: cs.primary)),
          Slider(
            value: idx.toDouble(),
            min: 0,
            max: (diskSteps.length - 1).toDouble(),
            divisions: diskSteps.length - 1,
            onChanged: (x) => setState(() => _diskMb = diskSteps[x.round()]),
          ),
          Text(
            '${t('Dosya başta birkaç KB\'tır, sistem yazdıkça büyür. Anlık görüntü ve "durumu kaydet" için gereklidir.', 'The file starts at a few KB and grows as the guest writes. Required for snapshots and "save state".')}'
            '${free != null ? '\n${t('Boş alan', 'Free space')}: ${fmtMb(free)}' : ''}',
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant, height: 1.4),
          ),
        ]),
      if (_diskMode == _DiskMode.existing)
        SectionCard(title: t('Disk dosyası', 'Disk file'), icon: Icons.save_rounded, children: [
          Row(children: [
            Expanded(
              child: Text(_existingDisk.isEmpty ? t('Seçilmedi', 'Not selected') : baseName(_existingDisk),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            FilledButton.tonal(onPressed: _busy ? null : _pickDisk, child: Text(t('Seç', 'Choose'))),
          ]),
        ]),
    ];
  }

  // ---------------------------------------------------------------- 4
  List<Widget> _stepSummary() {
    final cs = Theme.of(context).colorScheme;
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 120, child: Text(k, style: TextStyle(color: cs.onSurfaceVariant))),
            Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        );
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(children: [
            Row(children: [
              OsBadge(arch: _os.arch, label: _os.badge, size: 60),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_name.text.trim(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  Text('${_os.name} · ${archLabelOf(_os.arch)}', style: TextStyle(color: cs.onSurfaceVariant)),
                ]),
              ),
            ]),
            const Divider(height: 28),
            row('RAM', fmtMb(_vm.ramMb)),
            row(t('İşlemci', 'CPU'), '${_vm.cpus} ${t('çekirdek', 'cores')}'),
            row(t('Ekran kartı', 'Graphics'), _vm.vga),
            row(t('Ağ', 'Network'), _vm.net ? 'NAT · ${_vm.nic}' : t('Kapalı', 'Off')),
            row('CD / DVD', _vm.isoPath.isEmpty ? '—' : baseName(_vm.isoPath)),
            row(t('Disket', 'Floppy'), _vm.floppyPath.isEmpty ? '—' : baseName(_vm.floppyPath)),
            row(
              t('Disk', 'Disk'),
              switch (_diskMode) {
                _DiskMode.create => '${t('Yeni', 'New')} ${fmtMb(_diskMb)} qcow2',
                _DiskMode.existing => baseName(_existingDisk),
                _DiskMode.none => '—',
              },
            ),
            row(t('Önyükleme', 'Boot from'), mediaLabel(_vm.boot == 'disk' ? 'disk' : _vm.boot)),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        t('Tüm ayarlar daha sonra "Ayarlar" ekranından değiştirilebilir.',
            'All settings can be changed later from the "Settings" screen.'),
        textAlign: TextAlign.center,
        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
      ),
    ];
  }
}

class _OsPreview extends StatelessWidget {
  const _OsPreview({required this.os});
  final OsType os;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [archColor(os.arch).withOpacity(0.22), archColor(os.arch).withOpacity(0.04)],
        ),
      ),
      child: Row(children: [
        OsBadge(arch: os.arch, label: os.badge, size: 52),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(os.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [
              InfoChip(archLabelOf(os.arch), color: archColor(os.arch)),
              InfoChip(fmtMb(os.ram), icon: Icons.memory_rounded),
              if (os.diskMb > 0) InfoChip(fmtMb(os.diskMb), icon: Icons.save_rounded),
            ]),
            if (os.tip.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(os.tip, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ],
          ]),
        ),
      ]),
    );
  }
}
