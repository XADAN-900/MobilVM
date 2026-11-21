import 'package:flutter/material.dart';

import 'state.dart';

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
        'createdAt': createdAt,
        'lastRunAt': lastRunAt,
      };

  VmConfig copy() => VmConfig.fromMap(toMap());

  bool get hasMedia => isoPath.isNotEmpty || diskPath.isNotEmpty || floppyPath.isNotEmpty;

  String get archLabel => archLabelOf(arch);

  VmTemplate get tpl => templateById(template);
}

String archLabelOf(String arch) => switch (arch) {
      'x86_16' => '16-bit',
      'x86_32' => '32-bit',
      _ => '64-bit',
    };

/// Logodaki üç katmanın renkleri: 16-bit camgöbeği, 32-bit çivit, 64-bit mor.
List<Color> archGradient(String arch) => switch (arch) {
      'x86_16' => const [Color(0xFF67E8F9), Color(0xFF0891B2)],
      'x86_32' => const [Color(0xFFA5B4FC), Color(0xFF4F46E5)],
      _ => const [Color(0xFFDDD6FE), Color(0xFF7C3AED)],
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

/// Hazır sistem şablonları.
class VmTemplate {
  final String id;
  final String name;
  final String badge;
  final String arch;
  final String machine;
  final String cpu;
  final String vga;
  final String nic;
  final String boot;
  final int ram;
  final int cpus;
  final int diskMb;
  final bool net;
  final bool tablet;
  final String tipTr;
  final String tipEn;

  const VmTemplate({
    required this.id,
    required this.name,
    required this.badge,
    required this.arch,
    this.machine = 'pc',
    this.cpu = '',
    this.vga = 'std',
    this.nic = 'e1000',
    this.boot = 'cd',
    required this.ram,
    this.cpus = 1,
    required this.diskMb,
    this.net = true,
    this.tablet = true,
    required this.tipTr,
    required this.tipEn,
  });

  String get tip => t(tipTr, tipEn);

  VmConfig create() => VmConfig(
        name: id == 'custom' ? t('Yeni VM', 'New VM') : name,
        template: id,
        arch: arch,
        machine: machine,
        cpuModel: cpu,
        ramMb: ram,
        cpus: cpus,
        vga: vga,
        net: net,
        nic: nic,
        boot: boot,
        tablet: tablet,
        keyboard: (app.settings['keyboard'] as String?) ?? 'en-us',
      );
}

const templates = <VmTemplate>[
  VmTemplate(
    id: 'custom', name: 'Custom', badge: '⚙', arch: 'x86_64', ram: 1024, cpus: 2, diskMb: 8192,
    tipTr: 'Her şeyi kendin ayarla', tipEn: 'Configure everything yourself'),
  VmTemplate(
    id: 'freedos', name: 'FreeDOS', badge: 'FD', arch: 'x86_16', cpu: '486', vga: 'cirrus', ram: 32,
    diskMb: 512, net: false, tablet: false,
    tipTr: 'Ücretsiz DOS. ISO\'dan kur, oyunlar için ideal', tipEn: 'Free DOS. Install from ISO, great for games'),
  VmTemplate(
    id: 'msdos', name: 'MS-DOS', badge: 'DOS', arch: 'x86_16', cpu: '486', vga: 'cirrus', ram: 16,
    diskMb: 256, boot: 'floppy', net: false, tablet: false,
    tipTr: 'Kurulum disketi (.img) ile açılır', tipEn: 'Boots from a setup floppy (.img)'),
  VmTemplate(
    id: 'win31', name: 'Windows 3.1', badge: '3.1', arch: 'x86_16', cpu: '486', vga: 'cirrus', ram: 32,
    diskMb: 256, net: false, tablet: false,
    tipTr: 'Önce DOS kur, sonra Windows 3.1', tipEn: 'Install DOS first, then Windows 3.1'),
  VmTemplate(
    id: 'win98', name: 'Windows 98', badge: '98', arch: 'x86_32', cpu: 'pentium2', vga: 'cirrus', nic: 'pcnet',
    ram: 256, diskMb: 4096, tablet: false,
    tipTr: 'Touchpad fare modu önerilir', tipEn: 'Trackpad mouse mode recommended'),
  VmTemplate(
    id: 'winxp', name: 'Windows XP', badge: 'XP', arch: 'x86_32', cpu: 'pentium3', vga: 'cirrus', nic: 'rtl8139',
    ram: 512, diskMb: 10240,
    tipTr: 'Telefonda en dengeli Windows', tipEn: 'The most balanced Windows on a phone'),
  VmTemplate(
    id: 'win7', name: 'Windows 7', badge: '7', arch: 'x86_64', vga: 'std', ram: 2048, cpus: 2, diskMb: 32768,
    tipTr: 'Ağır: güçlü telefon ve sabır ister', tipEn: 'Heavy: needs a strong phone and patience'),
  VmTemplate(
    id: 'alpine', name: 'Alpine Linux', badge: 'AL', arch: 'x86_64', ram: 512, cpus: 2, diskMb: 4096,
    tipTr: 'Çok hafif Linux. SSH: tcp:2222:22', tipEn: 'Very light Linux. SSH: tcp:2222:22'),
  VmTemplate(
    id: 'debian', name: 'Debian', badge: 'DEB', arch: 'x86_64', ram: 1024, cpus: 2, diskMb: 16384,
    tipTr: 'Netinst ISO ile metin modunda kur', tipEn: 'Install netinst ISO in text mode'),
  VmTemplate(
    id: 'linux32', name: 'Linux 32-bit', badge: 'L32', arch: 'x86_32', cpu: 'pentium3', ram: 512, diskMb: 8192,
    tipTr: 'antiX, Tiny Core gibi 32-bit dağıtımlar', tipEn: '32-bit distros like antiX, Tiny Core'),
];

VmTemplate templateById(String id) =>
    templates.firstWhere((x) => x.id == id, orElse: () => templates.first);
