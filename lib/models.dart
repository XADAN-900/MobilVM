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
        'createdAt': createdAt,
        'lastRunAt': lastRunAt,
      };

  VmConfig copy() => VmConfig.fromMap(toMap());

  bool get hasMedia => isoPath.isNotEmpty || diskPath.isNotEmpty || floppyPath.isNotEmpty;

  String get archLabel => archLabelOf(arch);

  OsType get os => osById(template);

  bool get snapshotCapable => diskPath.toLowerCase().endsWith('.qcow2') || diskPath.toLowerCase().endsWith('.qcow');
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


/// Seçilen dosyanın türünü tahmin eder: 'cd', 'floppy', 'disk' ya da belirsizse null.
String? classifyMedia(String path) {
  final n = path.toLowerCase();
  final ext = n.contains('.') ? n.substring(n.lastIndexOf('.') + 1) : '';
  switch (ext) {
    case 'iso':
    case 'cdr':
    case 'bin':
    case 'toast':
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
