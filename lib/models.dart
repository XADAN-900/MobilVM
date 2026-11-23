import 'dart:io';

import 'package:flutter/material.dart';

import 'os_catalog.dart';
import 'state.dart';

export 'os_catalog.dart';

/// Java tarafındaki VmConfig.java ile birebir aynı alanlar.
class VmConfig {
  String id;
  String name;
  String template;
  String arch;
  String machine;
  String cpuModel;
  int ramMb;
  int cpus;
  String vga;
  bool net;
  String nic;
  String portForwards;
  String isoPath;
  String diskPath;
  String floppyPath;
  String boot;
  String keyboard;
  bool tablet;
  bool rtcLocal;
  String extraArgs;
  bool savedState;
  bool sharedFolder;
  String firmware;
  String sound;
  bool clipboard;
  bool sharedWritable;
  String kernelPath;
  String initrdPath;
  String kernelArgs;
  String biosPath;
  String diskBus;
  int createdAt;
  int lastRunAt;

  VmConfig({
    this.id = '',
    this.name = 'VM',
    this.template = 'custom',
    this.arch = 'x86_64',
    this.machine = 'pc',
    this.cpuModel = '',
    this.ramMb = 1024,
    this.cpus = 2,
    this.vga = 'std',
    this.net = true,
    this.nic = 'e1000',
    this.portForwards = '',
    this.isoPath = '',
    this.diskPath = '',
    this.floppyPath = '',
    this.boot = 'cd',
    this.keyboard = 'en-us',
    this.tablet = true,
    this.rtcLocal = true,
    this.extraArgs = '',
    this.savedState = false,
    this.sharedFolder = false,
    this.firmware = 'bios',
    this.sound = 'auto',
    this.clipboard = true,
    this.sharedWritable = false,
    this.kernelPath = '',
    this.initrdPath = '',
    this.kernelArgs = '',
    this.biosPath = '',
    this.diskBus = 'ide',
    this.createdAt = 0,
    this.lastRunAt = 0,
  });

  factory VmConfig.fromMap(Map m) {
    String s(String k, String d) => (m[k] as String?) ?? d;
    int n(String k, int d) => (m[k] as num?)?.toInt() ?? d;
    bool b(String k, bool d) => (m[k] as bool?) ?? d;
    return VmConfig(
      id: s('id', ''),
      name: s('name', 'VM'),
      template: s('template', 'custom'),
      arch: s('arch', 'x86_64'),
      machine: s('machine', 'pc'),
      cpuModel: s('cpuModel', ''),
      ramMb: n('ramMb', 512),
      cpus: n('cpus', 1),
      vga: s('vga', 'std'),
      net: b('net', false),
      nic: s('nic', 'e1000'),
      portForwards: s('portForwards', ''),
      isoPath: s('isoPath', ''),
      diskPath: s('diskPath', ''),
      floppyPath: s('floppyPath', ''),
      boot: s('boot', 'cd'),
      keyboard: s('keyboard', 'en-us'),
      tablet: b('tablet', true),
      rtcLocal: b('rtcLocal', true),
      extraArgs: s('extraArgs', ''),
      savedState: b('savedState', false),
      sharedFolder: b('sharedFolder', false),
      firmware: s('firmware', 'bios'),
      sound: s('sound', 'auto'),
      clipboard: b('clipboard', true),
      sharedWritable: b('sharedWritable', false),
      kernelPath: s('kernelPath', ''),
      initrdPath: s('initrdPath', ''),
      kernelArgs: s('kernelArgs', ''),
      biosPath: s('biosPath', ''),
      diskBus: s('diskBus', 'ide'),
      createdAt: n('createdAt', 0),
      lastRunAt: n('lastRunAt', 0),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'template': template,
        'arch': arch,
        'machine': machine,
        'cpuModel': cpuModel,
        'ramMb': ramMb,
        'cpus': cpus,
        'vga': vga,
        'net': net,
        'nic': nic,
        'portForwards': portForwards,
        'isoPath': isoPath,
        'diskPath': diskPath,
        'floppyPath': floppyPath,
        'boot': boot,
        'keyboard': keyboard,
        'tablet': tablet,
        'rtcLocal': rtcLocal,
        'extraArgs': extraArgs,
        'savedState': savedState,
        'sharedFolder': sharedFolder,
        'firmware': firmware,
        'sound': sound,
        'clipboard': clipboard,
        'sharedWritable': sharedWritable,
        'kernelPath': kernelPath,
        'initrdPath': initrdPath,
        'kernelArgs': kernelArgs,
        'biosPath': biosPath,
        'diskBus': diskBus,
        'createdAt': createdAt,
        'lastRunAt': lastRunAt,
      };

  VmConfig copy() => VmConfig.fromMap(toMap());

  bool get hasMedia => isoPath.isNotEmpty || diskPath.isNotEmpty || floppyPath.isNotEmpty || kernelPath.isNotEmpty;

  /// Bu VM verilen dosyayı kullanıyor mu (kütüphane temizliği ve "kullanımda" etiketi için)?
  bool uses(String path) =>
      path.isNotEmpty &&
      (isoPath == path || diskPath == path || floppyPath == path || kernelPath == path || initrdPath == path ||
          biosPath == path);

  /// Yazılabilir paylaşılan klasör (vvfat) anlık görüntü desteklemez.
  bool get _writableShare => sharedFolder && sharedWritable;

  /// Açılış için eksik bir şey varsa açıklaması (Java QemuArgs.bootProblem ile aynı kural).
  String? get bootProblem {
    if (arch != 'm68k' || kernelPath.isNotEmpty) return null;
    if (machine != 'virt' && biosPath.isNotEmpty) return null;
    return machine == 'virt'
        ? t('68k virt makinesi bir Linux çekirdeğiyle açılır: Gelişmiş açılış → Çekirdek.',
            'The 68k virt machine boots a Linux kernel: Advanced boot → Kernel.')
        : t('Quadra 800 için Macintosh ROM dosyası (Gelişmiş açılış → BIOS / ROM) ya da bir Linux çekirdeği gerekir.',
            'Quadra 800 needs a Macintosh ROM file (Advanced boot → BIOS / ROM) or a Linux kernel.');
  }

  String get archLabel => archLabelOf(arch);

  OsType get os => osById(template);

  bool get qcow2 => diskPath.toLowerCase().endsWith('.qcow2') || diskPath.toLowerCase().endsWith('.qcow');

  /// Anlık görüntü: qcow2 disk gerekir.
  bool get snapshotCapable => qcow2 && !_writableShare;

  /// Bellek dahil durum kaydetme: UEFI değişken dosyası (pflash) olan VM'lerde QEMU izin vermez.
  bool get saveStateCapable => qcow2 && !usesUefi && !_writableShare;

  bool get usesUefi =>
      biosPath.isEmpty &&
      (arch == 'arm64' || arch == 'arm32' || arch == 'riscv64' || (isX86Arch(arch) && arch != 'x86_16' && firmware == 'uefi'));
}

/// Desteklenen tüm mimariler (sıralı).
const allArchs = ['x86_16', 'x86_32', 'x86_64', 'arm64', 'arm32', 'ppc', 'ppc64', 'riscv64', 'm68k'];

bool isX86Arch(String arch) => arch.startsWith('x86');

/// İşlemci ailesi: x86, arm, ppc, riscv
String archFamilyOf(String arch) => switch (arch) {
      'arm64' || 'arm32' => 'arm',
      'ppc' || 'ppc64' => 'ppc',
      'riscv64' => 'riscv',
      'm68k' => 'm68k',
      _ => 'x86',
    };

String archLabelOf(String arch) => switch (arch) {
      'x86_16' => '16-bit',
      'x86_32' => '32-bit',
      'x86_64' => '64-bit',
      'arm64' => 'ARM 64',
      'arm32' => 'ARM 32',
      'ppc' => 'PowerPC 32',
      'ppc64' => 'PowerPC 64',
      'riscv64' => 'RISC-V 64',
      'm68k' => '68k',
      _ => arch,
    };

/// Uzun açıklama (mimari seçim listesi için).
String archLongLabelOf(String arch) => switch (arch) {
      'x86_16' => 'x86 · 16-bit (DOS, Windows 3.x)',
      'x86_32' => 'x86 · 32-bit (Windows 9x/XP, Linux)',
      'x86_64' => 'x86 · 64-bit (Windows 7+, Linux)',
      'arm64' => 'ARM · 64-bit (AArch64)',
      'arm32' => 'ARM · 32-bit (ARMv7)',
      'ppc' => 'PowerPC · 32-bit (PowerMac G4)',
      'ppc64' => 'PowerPC · 64-bit (IBM POWER9)',
      'riscv64' => 'RISC-V · 64-bit',
      'm68k' => 'Motorola 68k · 32-bit (Macintosh Quadra)',
      _ => arch,
    };

/// Logodaki üç katmanın renkleri: 16-bit camgöbeği, 32-bit çivit, 64-bit mor.
/// Diğer aileler: ARM yeşil, PowerPC turuncu, RISC-V sarı.
List<Color> archGradient(String arch) => switch (arch) {
      'x86_16' => const [Color(0xFF67E8F9), Color(0xFF0891B2)],
      'x86_32' => const [Color(0xFFA5B4FC), Color(0xFF4F46E5)],
      'arm64' || 'arm32' => const [Color(0xFF86EFAC), Color(0xFF16A34A)],
      'ppc' || 'ppc64' => const [Color(0xFFFDBA74), Color(0xFFEA580C)],
      'riscv64' => const [Color(0xFFFDE68A), Color(0xFFD97706)],
      'm68k' => const [Color(0xFFFDA4AF), Color(0xFFE11D48)],
      _ => const [Color(0xFFDDD6FE), Color(0xFF7C3AED)],
    };

/// x86 dışı mimarilerde donanım sabittir: makine + firmware.
String archMachineLabel(String arch) => switch (arch) {
      'arm64' || 'arm32' => 'ARM virt · UEFI (edk2)',
      'ppc' => 'PowerMac G4 (mac99) · OpenBIOS',
      'ppc64' => 'IBM pSeries (POWER9) · SLOF',
      'riscv64' => 'RISC-V virt · OpenSBI + UEFI',
      'm68k' => 'Macintosh Quadra 800 · Mac ROM / Linux',
      _ => 'PC',
    };

/// Mimarinin kabul ettiği en fazla RAM ve çekirdek (Java QemuArgs ile aynı).
int archMaxRam(String arch) => switch (arch) { 'x86_16' => 256, 'm68k' => 1024, 'ppc' => 2048, 'arm32' => 3072, _ => 65536 };
int archMaxCpus(String arch) => arch == 'ppc' || arch == 'x86_16' || arch == 'm68k' ? 1 : 16;

/// Ses kartı seçenekleri (mimariye göre). "auto" Java tarafında sisteme göre seçilir.
Map<String, String> soundOptions(VmConfig v) {
  final auto = t('Otomatik', 'Automatic');
  final off = t('Kapalı', 'Off');
  if (v.arch == 'm68k') return {'auto': '$auto (Apple Sound Chip)', 'none': off};
  final isa = isX86Arch(v.arch) && v.machine == 'isapc';
  return {
    'auto': auto,
    'none': off,
    if (isX86Arch(v.arch)) 'sb16': 'Sound Blaster 16 + AdLib',
    if (!isa) ...{
      'ac97': 'Intel AC97',
      'es1370': 'Ensoniq ES1370',
      'hda': 'Intel HD Audio',
      'virtio': 'VirtIO Sound',
    },
  };
}

/// Ortak pano (virtio-serial + vdagent) bu VM'de kullanılabilir mi? (Java clipboardCapable ile aynı)
bool clipboardCapable(VmConfig v) {
  if (v.arch == 'x86_16' || v.arch == 'ppc' || v.arch == 'm68k') return false;
  if (legacySoundTemplates.contains(v.template)) return false;
  return !(isX86Arch(v.arch) && v.machine == 'isapc');
}

/// DOS, Windows 1-3.x ve 9x: Sound Blaster dünyası (Java SB16_TEMPLATES ile aynı).
const legacySoundTemplates = {
  'win1', 'win2', 'win31', 'win95', 'win98', 'winme', 'freedos', 'msdos', 'drdos', 'pcdos', 'dos_other', 'other16',
  'win9x_other',
};

Color archColor(String arch) => archGradient(arch)[1];

String fmtMb(int mb) {
  if (mb >= 1024) {
    final gb = mb / 1024;
    return '${gb == gb.roundToDouble() ? gb.toStringAsFixed(0) : gb.toStringAsFixed(1)} GB';
  }
  return '$mb MB';
}

String fmtBytes(int b) {
  if (b >= 1 << 30) return '${(b / (1 << 30)).toStringAsFixed(1)} GB';
  if (b >= 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(0)} MB';
  if (b >= 1 << 10) return '${(b / (1 << 10)).toStringAsFixed(0)} KB';
  return '$b B';
}

String baseName(String path) => path.isEmpty ? '' : path.split('/').last;


/// Seçilen dosyanın türünü tahmin eder: 'cd', 'floppy', 'disk' ya da belirsizse null.
String? classifyMedia(String path) {
  final n = path.toLowerCase();
  final ext = n.contains('.') ? n.substring(n.lastIndexOf('.') + 1) : '';
  switch (ext) {
    case 'iso':
    case 'cdr':
    case 'bin':
    case 'toast':
    case 'dmg':
      return 'cd';
    case 'ima':
    case 'flp':
    case 'vfd':
    case 'dsk':
      return 'floppy';
    case 'qcow2':
    case 'qcow':
    case 'vdi':
    case 'vmdk':
    case 'vhd':
    case 'vhdx':
      return 'disk';
  }
  // .img ve benzerleri: disket boyutundaysa (≤ 2.88 MB) disket
  try {
    final size = File(path).lengthSync();
    if (size > 0 && size <= 2949120) return 'floppy';
  } catch (_) {}
  return null;
}

String mediaLabel(String kind) => switch (kind) {
      'floppy' => t('Disket', 'Floppy'),
      'disk' => t('Sabit disk', 'Hard disk'),
      _ => 'CD/DVD',
    };
