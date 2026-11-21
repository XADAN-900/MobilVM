import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../backend.dart';
import '../models.dart';
import '../state.dart';
import '../widgets/common.dart';
import 'wizard_screen.dart' show ramSteps, diskSteps;

const _ramSteps = ramSteps;
const _diskSteps = diskSteps;

const keyboardLayouts = {
  'en-us': 'English (US)',
  'tr': 'Türkçe Q',
  'en-gb': 'English (UK)',
  'de': 'Deutsch',
  'fr': 'Français',
  'es': 'Español',
  'it': 'Italiano',
  'pt-br': 'Português (BR)',
  'ru': 'Русский',
  'ja': '日本語',
};

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, this.vm});
  final VmConfig? vm;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late VmConfig v;
  late bool isNew;
  late final TextEditingController _name;
  late final TextEditingController _cpu;
  late final TextEditingController _extra;
  late final TextEditingController _ports;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    isNew = widget.vm == null;
    v = widget.vm?.copy() ?? osById('custom').create();
    _name = TextEditingController(text: v.name);
    _cpu = TextEditingController(text: v.cpuModel);
    _extra = TextEditingController(text: v.extraArgs);
    _ports = TextEditingController(text: v.portForwards);
  }

  @override
  void dispose() {
    _name.dispose();
    _cpu.dispose();
    _extra.dispose();
    _ports.dispose();
    super.dispose();
  }

  int get _maxRam {
    final cap = v.arch == 'x86_16' ? 256 : 16384;
    return math.min(cap, math.max(64, (app.totalRamMb * 0.6).floor()));
  }

  List<int> get _ramOptions {
    final l = _ramSteps.where((s) => s <= _maxRam).toList();
    if (!l.contains(v.ramMb)) {
      l
        ..add(v.ramMb)
        ..sort();
    }
    return l;
  }

  /// VirtualBox gibi: sürüm değişince yalnızca tür kaydı değişir; istenirse önerilen donanım uygulanır.
  void _setOs(OsType os) {
    setState(() {
      v.template = os.id;
      if (v.arch != os.arch) _setArchInner(os.arch);
    });
  }

  void _applyRecommended() {
    final os = v.os;
    setState(() {
      os.applyTo(v);
      _cpu.text = v.cpuModel;
      if (v.ramMb > _maxRam) v.ramMb = _ramSteps.lastWhere((s) => s <= _maxRam);
      v.cpus = math.min(v.cpus, math.max(1, math.min(app.cores, 8)));
    });
    toast(context, t('Önerilen ayarlar uygulandı', 'Recommended settings applied'));
  }

  void _setArch(String arch) => setState(() => _setArchInner(arch));

  void _setArchInner(String arch) {
    v.arch = arch;
    v.cpuModel = '';
    _cpu.text = '';
    if (arch == 'x86_16') {
      v.vga = 'cirrus';
      v.tablet = false;
      if (v.ramMb > 256) v.ramMb = 32;
      v.cpus = 1;
    } else if (arch == 'x86_32') {
      if (v.vga == 'std' && isNew) v.vga = 'cirrus';
    } else {
      if (v.vga == 'cirrus' && isNew) v.vga = 'std';
    }
    if (v.ramMb > _maxRam) v.ramMb = _ramSteps.lastWhere((s) => s <= _maxRam);
  }

  /// Dosyayı seçer; türü farklıysa (ör. ISO satırına disket) doğru yere koyar.
  Future<void> _pickInto(String slot) async {
    try {
      final p = await app.pickFile();
      if (p == null) return;
      final kind = classifyMedia(p) ?? slot;
      setState(() {
        switch (kind) {
          case 'floppy':
            v.floppyPath = p;
            if (v.isoPath.isEmpty) v.boot = 'floppy';
            break;
          case 'disk':
            v.diskPath = p;
            if (v.isoPath.isEmpty && v.floppyPath.isEmpty) v.boot = 'disk';
            break;
          default:
            v.isoPath = p;
            v.boot = 'cd';
        }
      });
      if (kind != slot && mounted) toast(context, '${baseName(p)} → ${mediaLabel(kind)}');
      // Dosyadan sistem tanındıysa türü/sürümü değiştirmeyi öner
      final d = await detectOsFromFile(p);
      if (d != null && d.os.id != v.os.id && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 8),
          content: Text('${t('Algılandı', 'Detected')}: ${d.os.name}'),
          action: SnackBarAction(
            label: t('Uygula', 'Apply'),
            onPressed: () {
              if (!mounted) return;
              setState(() {
                d.os.applyTo(v);
                _cpu.text = v.cpuModel;
                if (v.ramMb > _maxRam) v.ramMb = _ramSteps.lastWhere((s) => s <= _maxRam);
                v.cpus = math.min(v.cpus, math.max(1, math.min(app.cores, 8)));
                v.boot = kind == 'floppy' ? 'floppy' : kind == 'disk' ? 'disk' : 'cd';
              });
            },
          ),
        ));
      }
    } catch (e) {
      if (mounted) toast(context, '${t('Dosya alınamadı', 'Could not import file')}: $e');
    }
  }

  Future<void> _createDisk() async {
    var idx = _diskSteps.indexOf(v.os.diskMb);
    if (idx < 0) idx = 7;
    final free = (app.device['freeMb'] as num?)?.toInt();
    final size = await showDialog<int>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(t('Yeni sanal disk', 'New virtual disk')),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(fmtMb(_diskSteps[idx]), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
            Slider(
              value: idx.toDouble(),
              min: 0,
              max: (_diskSteps.length - 1).toDouble(),
              divisions: _diskSteps.length - 1,
              onChanged: (x) => set(() => idx = x.round()),
            ),
            Text(
              t('qcow2 biçimi: dosya başta birkaç KB\'tır, sistem yazdıkça büyür.',
                  'qcow2 format: the file starts at a few KB and grows as the guest writes.'),
              style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant, fontSize: 13),
            ),
            if (free != null) ...[
              const SizedBox(height: 6),
              Text('${t('Telefondaki boş alan', 'Free space on phone')}: ${fmtMb(free)}',
                  style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant, fontSize: 13)),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: Text(t('Vazgeç', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(c, _diskSteps[idx]), child: Text(t('Oluştur', 'Create'))),
          ],
        ),
      ),
    );
    if (size == null) return;
    setState(() => _busy = true);
    try {
      final name = _name.text.trim().isEmpty ? 'disk' : _name.text.trim();
      final p = await Backend.call<String>('createDisk', {'name': name, 'sizeMb': size});
      if (p != null) {
        setState(() {
          v.diskPath = p;
          if (v.isoPath.isEmpty && v.floppyPath.isEmpty) v.boot = 'disk';
        });
      }
    } catch (e) {
      if (mounted) toast(context, '${t('Disk oluşturulamadı', 'Could not create disk')}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    v.name = _name.text.trim().isEmpty ? 'VM' : _name.text.trim();
    v.cpuModel = _cpu.text.trim();
    v.extraArgs = _extra.text.trim();
    v.portForwards = _ports.text.trim();
    await app.save(v);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxCpu = math.max(1, math.min(app.cores, 8));
    final ramOpts = _ramOptions;
    final ramIdx = ramOpts.indexOf(v.ramMb);

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? t('Yeni sanal makine', 'New virtual machine') : v.name),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(onPressed: _busy ? null : _save, child: Text(t('Kaydet', 'Save'))),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          const ImportBanner(),
          if (_busy) const LinearProgressIndicator(),

          if (app.runningId == v.id && v.id.isNotEmpty)
            Card(
              color: cs.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  t('VM çalışıyor. Değişiklikler bir sonraki açılışta geçerli olur.',
                      'The VM is running. Changes apply on the next start.'),
                  style: TextStyle(color: cs.onTertiaryContainer),
                ),
              ),
            ),
          if (v.savedState)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Card(
                color: cs.tertiaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    t('Bu VM\'in kayıtlı durumu var. Donanım değişirse kayıtlı durum yüklenemez; o zaman "Durumu at" de.',
                        'This VM has a saved state. If hardware changes it can\'t be restored; then choose "Discard".'),
                    style: TextStyle(color: cs.onTertiaryContainer),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          SectionCard(title: t('İşletim sistemi', 'Operating system'), icon: Icons.computer_rounded, children: [
            DropdownButtonFormField<String>(
              key: ValueKey('fam-${v.os.family}'),
              value: v.os.family,
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
                if (f != null && f != v.os.family) _setOs(osOfFamily(f).first);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('ver-${v.os.id}'),
              value: v.os.id,
              isExpanded: true,
              decoration: InputDecoration(labelText: t('Sürüm', 'Version')),
              items: [
                for (final o in osOfFamily(v.os.family))
                  DropdownMenuItem(
                    value: o.id,
                    child: Row(children: [
                      OsBadge(arch: o.arch, label: o.badge, size: 26),
                      const SizedBox(width: 10),
                      Expanded(child: Text(o.name, overflow: TextOverflow.ellipsis)),
                    ]),
                  ),
              ],
              onChanged: (id) {
                if (id != null) _setOs(osById(id));
              },
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Text(v.os.tip, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              ),
              TextButton.icon(
                onPressed: _applyRecommended,
                icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                label: Text(t('Önerilen ayarlar', 'Recommended')),
              ),
            ]),
          ]),
          const SizedBox(height: 12),

          // ---------------------------------------------------- genel
          SectionCard(title: t('Genel', 'General'), icon: Icons.badge_outlined, children: [
            TextField(controller: _name, decoration: InputDecoration(labelText: t('Ad', 'Name'))),
            const SizedBox(height: 14),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'x86_16', label: Text('16-bit')),
                ButtonSegment(value: 'x86_32', label: Text('32-bit')),
                ButtonSegment(value: 'x86_64', label: Text('64-bit')),
              ],
              selected: {v.arch},
              onSelectionChanged: (s) => _setArch(s.first),
            ),
            const SizedBox(height: 8),
            Text(
              switch (v.arch) {
                'x86_16' => t('DOS, Windows 3.x · 486 işlemci', 'DOS, Windows 3.x · 486 CPU'),
                'x86_32' => t('Windows 95/98/XP, 32-bit Linux', 'Windows 95/98/XP, 32-bit Linux'),
                _ => t('Modern Linux, Windows 7+', 'Modern Linux, Windows 7+'),
              },
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
            ),
          ]),
          const SizedBox(height: 12),

          // ---------------------------------------------------- donanım
          SectionCard(title: t('Donanım', 'Hardware'), icon: Icons.memory_rounded, children: [
            _sliderRow(
              'RAM',
              fmtMb(v.ramMb),
              Slider(
                value: ramIdx.toDouble(),
                min: 0,
                max: (ramOpts.length - 1).toDouble(),
                divisions: math.max(1, ramOpts.length - 1),
                onChanged: (x) => setState(() => v.ramMb = ramOpts[x.round()]),
              ),
              '${t('Cihazda', 'Device has')} ${fmtMb(app.totalRamMb)}',
            ),
            _sliderRow(
              t('İşlemci çekirdeği', 'CPU cores'),
              '${v.cpus}',
              Slider(
                value: v.cpus.clamp(1, maxCpu).toDouble(),
                min: 1,
                max: maxCpu.toDouble(),
                divisions: math.max(1, maxCpu - 1),
                onChanged: maxCpu == 1 ? null : (x) => setState(() => v.cpus = x.round()),
              ),
              null,
            ),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: _dropdown<String>(
                  t('Ekran kartı', 'Graphics'),
                  v.vga,
                  const {'std': 'Standard VGA', 'cirrus': 'Cirrus Logic', 'vmware': 'VMware SVGA', 'virtio': 'VirtIO GPU'},
                  (x) => setState(() => v.vga = x),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _dropdown<String>(
                  t('Anakart', 'Machine'),
                  v.machine,
                  const {'pc': 'i440FX (PC)', 'q35': 'Q35 (modern)', 'isapc': 'ISA PC (eski)'},
                  (x) => setState(() => v.machine = x),
                ),
              ),
            ]),
          ]),
          const SizedBox(height: 12),

          // ---------------------------------------------------- depolama
          SectionCard(title: t('Depolama', 'Storage'), icon: Icons.storage_rounded, children: [
            _mediaTile(
              Icons.album_rounded,
              t('CD / DVD (ISO, BIN, IMG)', 'CD / DVD (ISO, BIN, IMG)'),
              v.isoPath,
              [
                _act(t('Seç', 'Choose'), () => _pickInto('cd')),
              ],
              () => setState(() => v.isoPath = ''),
            ),
            _mediaTile(
              Icons.save_rounded,
              t('Sabit disk (IMG, QCOW2, VDI, VMDK, VHD)', 'Hard disk (IMG, QCOW2, VDI, VMDK, VHD)'),
              v.diskPath,
              [
                _act(t('Yeni', 'New'), _createDisk),
                _act(t('Seç', 'Choose'), () => _pickInto('disk')),
              ],
              () => setState(() => v.diskPath = ''),
            ),
            _mediaTile(
              Icons.sd_card_rounded,
              t('Disket (IMG, IMA, FLP, VFD)', 'Floppy (IMG, IMA, FLP, VFD)'),
              v.floppyPath,
              [_act(t('Seç', 'Choose'), () => _pickInto('floppy'))],
              () => setState(() => v.floppyPath = ''),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: v.sharedFolder,
              onChanged: (x) => setState(() => v.sharedFolder = x),
              title: Text(t('Paylaşılan klasör', 'Shared folder')),
              subtitle: Text(t('Telefondan eklenen dosyalar VM\'de FAT sürücü olarak görünür (Ayrıntılar ekranından dosya ekle)',
                  'Files added from the phone appear as a FAT drive in the VM (add files from the Details screen)')),
            ),
            const SizedBox(height: 10),
            Text(t('Önyükleme sırası', 'Boot from'), style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'cd', icon: const Icon(Icons.album_rounded), label: const Text('CD')),
                ButtonSegment(value: 'disk', icon: const Icon(Icons.save_rounded), label: Text(t('Disk', 'Disk'))),
                ButtonSegment(value: 'floppy', icon: const Icon(Icons.sd_card_rounded), label: Text(t('Disket', 'Floppy'))),
              ],
              selected: {v.boot},
              onSelectionChanged: (s) => setState(() => v.boot = s.first),
            ),
          ]),
          const SizedBox(height: 12),

          // ---------------------------------------------------- ağ
          SectionCard(title: t('Ağ', 'Network'), icon: Icons.lan_rounded, children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: v.net,
              onChanged: (x) => setState(() => v.net = x),
              title: Text(t('İnternet erişimi (NAT)', 'Internet access (NAT)')),
              subtitle: Text(t('Telefonun bağlantısını paylaşır', 'Shares the phone\'s connection')),
            ),
            if (v.net) ...[
              _dropdown<String>(
                t('Ağ kartı', 'Network card'),
                v.nic,
                const {
                  'e1000': 'Intel e1000',
                  'rtl8139': 'Realtek RTL8139',
                  'pcnet': 'AMD PCnet',
                  'ne2k_pci': 'NE2000 PCI',
                  'virtio-net-pci': 'VirtIO',
                },
                (x) => setState(() => v.nic = x),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ports,
                decoration: InputDecoration(
                  labelText: t('Port yönlendirme', 'Port forwarding'),
                  hintText: 'tcp:2222:22, tcp:8080:80',
                  helperText: t('telefon_portu:misafir_portu', 'phone_port:guest_port'),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 12),

          // ---------------------------------------------------- giriş
          SectionCard(title: t('Giriş aygıtları', 'Input'), icon: Icons.keyboard_rounded, children: [
            _dropdown<String>(
              t('Klavye düzeni', 'Keyboard layout'),
              keyboardLayouts.containsKey(v.keyboard) ? v.keyboard : 'en-us',
              keyboardLayouts,
              (x) => setState(() => v.keyboard = x),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: v.tablet && v.machine != 'isapc',
              onChanged: v.machine == 'isapc' ? null : (x) => setState(() => v.tablet = x),
              title: Text(t('USB tablet (birebir dokunmatik)', 'USB tablet (absolute touch)')),
              subtitle: Text(t('Kapalıysa PS/2 fare kullanılır (DOS, Win 9x)', 'Off = PS/2 mouse (DOS, Win 9x)')),
            ),
          ]),
          const SizedBox(height: 12),

          // ---------------------------------------------------- gelişmiş
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              leading: Icon(Icons.science_outlined, color: cs.primary),
              title: Text(t('Gelişmiş', 'Advanced'), style: const TextStyle(fontWeight: FontWeight.w700)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              shape: const Border(),
              children: [
                TextField(
                  controller: _cpu,
                  decoration: InputDecoration(
                    labelText: t('İşlemci modeli', 'CPU model'),
                    hintText: switch (v.arch) { 'x86_16' => '486', 'x86_32' => 'pentium3', _ => 'max' },
                    helperText: t('Boş = otomatik', 'Empty = automatic'),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: v.rtcLocal,
                  onChanged: (x) => setState(() => v.rtcLocal = x),
                  title: Text(t('Saat yerel zamanda (Windows için)', 'Clock in local time (for Windows)')),
                ),
                TextField(
                  controller: _extra,
                  maxLines: 2,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: InputDecoration(
                    labelText: t('Ek QEMU parametreleri', 'Extra QEMU arguments'),
                    hintText: '-device sb16',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(t('Kaydet', 'Save'), style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget _sliderRow(String label, String value, Widget slider, String? hint) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(value, style: TextStyle(fontWeight: FontWeight.w800, color: cs.primary, fontSize: 16)),
      ]),
      slider,
      if (hint != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(hint, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ),
    ]);
  }

  Widget _dropdown<T>(String label, T value, Map<T, String> items, ValueChanged<T> onChanged) {
    return DropdownButtonFormField<T>(
      value: items.containsKey(value) ? value : items.keys.first,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final e in items.entries)
          DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (x) {
        if (x != null) onChanged(x);
      },
    );
  }

  Widget _act(String label, VoidCallback onTap) =>
      TextButton(onPressed: _busy ? null : onTap, child: Text(label));

  Widget _mediaTile(IconData icon, String title, String path, List<Widget> actions, VoidCallback onClear) {
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
                path.isEmpty ? t('Boş', 'Empty') : baseName(path),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ]),
          ),
          ...actions,
          if (path.isNotEmpty)
            IconButton(
              tooltip: t('Kaldır', 'Remove'),
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: onClear,
            ),
        ]),
      ),
    );
  }
}
