import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'models.dart';
import 'state.dart';

/// VirtualBox'taki gibi: önce tür (Windows, Linux...), sonra sürüm.
class OsFamily {
  final String id;
  final String nameTr;
  final String nameEn;
  final IconData icon;
  const OsFamily(this.id, this.nameTr, this.nameEn, this.icon);
  String get name => t(nameTr, nameEn);
}

const osFamilies = <OsFamily>[
  OsFamily('windows', 'Microsoft Windows', 'Microsoft Windows', Icons.desktop_windows_rounded),
  OsFamily('linux', 'Linux', 'Linux', Icons.terminal_rounded),
  OsFamily('dos', 'DOS', 'DOS', Icons.keyboard_rounded),
  OsFamily('bsd', 'BSD', 'BSD', Icons.dns_rounded),
  OsFamily('other', 'Diğer', 'Other', Icons.category_rounded),
];

OsFamily familyById(String id) => osFamilies.firstWhere((f) => f.id == id, orElse: () => osFamilies.last);

/// Bir işletim sistemi sürümü ve önerilen donanımı.
class OsType {
  final String id;
  final String family;
  final String name;
  final String badge;
  final String arch;
  final String machine;
  final String cpu;
  final String vga;
  final String nic;
  final String boot;
  final int ram;
  final int minRam;
  final int cpus;
  final int diskMb;
  final bool net;
  final bool tablet;
  final bool heavy;
  final String tipTr;
  final String tipEn;

  const OsType({
    required this.id,
    required this.family,
    required this.name,
    required this.badge,
    required this.arch,
    this.machine = 'pc',
    this.cpu = '',
    this.vga = 'std',
    this.nic = 'e1000',
    this.boot = 'cd',
    required this.ram,
    this.minRam = 0,
    this.cpus = 1,
    required this.diskMb,
    this.net = true,
    this.tablet = true,
    this.heavy = false,
    this.tipTr = '',
    this.tipEn = '',
  });

  String get tip => t(tipTr, tipEn);
  OsFamily get fam => familyById(family);

  /// Bu sürüm için önerilen ayarlarla yeni bir VM.
  VmConfig create() => applyTo(VmConfig(
        name: name,
        keyboard: (app.settings['keyboard'] as String?) ?? 'en-us',
      ));

  /// Önerilen donanımı mevcut bir VM'e uygular (medya ve ad korunur).
  VmConfig applyTo(VmConfig v) => v
    ..template = id
    ..arch = arch
    ..machine = machine
    ..cpuModel = cpu
    ..ramMb = ram
    ..cpus = cpus
    ..vga = vga
    ..net = net
    ..nic = nic
    ..boot = boot
    ..tablet = tablet;
}

const osCatalog = <OsType>[
  // ------------------------------------------------------------ Windows
  OsType(id: 'win31', family: 'windows', name: 'Windows 3.1', badge: '3.1', arch: 'x86_16', cpu: '486',
      vga: 'cirrus', ram: 32, diskMb: 256, net: false, tablet: false,
      tipTr: 'Önce MS-DOS kur, sonra Windows 3.1 disketlerini çalıştır',
      tipEn: 'Install MS-DOS first, then run the Windows 3.1 floppies'),
  OsType(id: 'win95', family: 'windows', name: 'Windows 95', badge: '95', arch: 'x86_32', cpu: 'pentium',
      vga: 'cirrus', nic: 'ne2k_pci', ram: 64, diskMb: 1024, tablet: false,
      tipTr: 'Touchpad fare modu önerilir', tipEn: 'Trackpad mouse mode recommended'),
  OsType(id: 'win98', family: 'windows', name: 'Windows 98', badge: '98', arch: 'x86_32', cpu: 'pentium2',
      vga: 'cirrus', nic: 'pcnet', ram: 256, diskMb: 4096, tablet: false,
      tipTr: '512 MB üstü RAM verme. Touchpad modu önerilir', tipEn: 'Do not exceed 512 MB RAM. Trackpad mode recommended'),
  OsType(id: 'winme', family: 'windows', name: 'Windows ME', badge: 'ME', arch: 'x86_32', cpu: 'pentium2',
      vga: 'cirrus', nic: 'pcnet', ram: 256, diskMb: 4096, tablet: false),
  OsType(id: 'win2k', family: 'windows', name: 'Windows 2000', badge: '2K', arch: 'x86_32', cpu: 'pentium3',
      vga: 'cirrus', nic: 'rtl8139', ram: 512, diskMb: 8192),
  OsType(id: 'winxp', family: 'windows', name: 'Windows XP', badge: 'XP', arch: 'x86_32', cpu: 'pentium3',
      vga: 'cirrus', nic: 'rtl8139', ram: 512, cpus: 1, diskMb: 10240,
      tipTr: 'Telefonda en dengeli Windows', tipEn: 'The most balanced Windows on a phone'),
  OsType(id: 'winvista', family: 'windows', name: 'Windows Vista', badge: 'VI', arch: 'x86_32', ram: 1024,
      cpus: 2, diskMb: 20480, heavy: true),
  OsType(id: 'win7_32', family: 'windows', name: 'Windows 7 (32-bit)', badge: '7', arch: 'x86_32', ram: 1024,
      cpus: 2, diskMb: 20480, heavy: true),
  OsType(id: 'win7', family: 'windows', name: 'Windows 7 (64-bit)', badge: '7', arch: 'x86_64', ram: 2048,
      cpus: 2, diskMb: 32768, heavy: true),
  OsType(id: 'win8', family: 'windows', name: 'Windows 8.1 (64-bit)', badge: '8', arch: 'x86_64', ram: 2048,
      cpus: 2, diskMb: 32768, heavy: true),
  OsType(id: 'win10_32', family: 'windows', name: 'Windows 10 (32-bit)', badge: '10', arch: 'x86_32', ram: 2048,
      cpus: 2, diskMb: 32768, heavy: true),
  OsType(id: 'win10', family: 'windows', name: 'Windows 10 (64-bit)', badge: '10', arch: 'x86_64', ram: 3072,
      cpus: 2, diskMb: 40960, heavy: true),
  OsType(id: 'win11', family: 'windows', name: 'Windows 11 (64-bit)', badge: '11', arch: 'x86_64', ram: 4096,
      cpus: 2, diskMb: 65536, heavy: true,
      tipTr: 'TPM/Güvenli Önyükleme kontrolünü atlatmak gerekir; çok yavaş çalışır',
      tipEn: 'Requires bypassing the TPM/Secure Boot check; runs very slowly'),

  // ------------------------------------------------------------ Linux
  OsType(id: 'alpine', family: 'linux', name: 'Alpine Linux', badge: 'AL', arch: 'x86_64', ram: 512, cpus: 2,
      diskMb: 4096, tipTr: 'Çok hafif. SSH için port: tcp:2222:22', tipEn: 'Very light. SSH port: tcp:2222:22'),
  OsType(id: 'debian', family: 'linux', name: 'Debian (64-bit)', badge: 'DEB', arch: 'x86_64', ram: 1024,
      cpus: 2, diskMb: 16384, tipTr: 'netinst ISO ile metin modunda kur', tipEn: 'Install the netinst ISO in text mode'),
  OsType(id: 'debian32', family: 'linux', name: 'Debian (32-bit)', badge: 'DEB', arch: 'x86_32', cpu: 'pentium3',
      ram: 768, diskMb: 12288),
  OsType(id: 'ubuntu', family: 'linux', name: 'Ubuntu (64-bit)', badge: 'UB', arch: 'x86_64', ram: 3072,
      cpus: 2, diskMb: 30720, heavy: true, tipTr: 'Server sürümü masaüstüden çok daha hızlıdır',
      tipEn: 'The server edition is much faster than desktop'),
  OsType(id: 'mint', family: 'linux', name: 'Linux Mint (64-bit)', badge: 'MNT', arch: 'x86_64', ram: 3072,
      cpus: 2, diskMb: 30720, heavy: true),
  OsType(id: 'arch', family: 'linux', name: 'Arch Linux (64-bit)', badge: 'ARC', arch: 'x86_64', ram: 1024,
      cpus: 2, diskMb: 16384),
  OsType(id: 'fedora', family: 'linux', name: 'Fedora (64-bit)', badge: 'FED', arch: 'x86_64', ram: 3072,
      cpus: 2, diskMb: 30720, heavy: true),
  OsType(id: 'tinycore', family: 'linux', name: 'Tiny Core Linux', badge: 'TC', arch: 'x86_32', cpu: 'pentium3',
      ram: 256, diskMb: 1024, tipTr: '~20 MB, saniyeler içinde açılır', tipEn: '~20 MB, boots in seconds'),
  OsType(id: 'antix', family: 'linux', name: 'antiX (32-bit)', badge: 'AX', arch: 'x86_32', cpu: 'pentium3',
      ram: 512, diskMb: 8192),
  OsType(id: 'linux32', family: 'linux', name: 'Linux (32-bit, diğer)', badge: 'L32', arch: 'x86_32',
      cpu: 'pentium3', ram: 512, diskMb: 8192),
  OsType(id: 'linux64', family: 'linux', name: 'Linux (64-bit, diğer)', badge: 'L64', arch: 'x86_64', ram: 1024,
      cpus: 2, diskMb: 16384),

  // ------------------------------------------------------------ DOS
  OsType(id: 'freedos', family: 'dos', name: 'FreeDOS', badge: 'FD', arch: 'x86_16', cpu: '486', vga: 'cirrus',
      ram: 32, diskMb: 512, net: false, tablet: false,
      tipTr: 'Ücretsiz ve modern DOS; eski oyunlar için ideal', tipEn: 'Free modern DOS; ideal for old games'),
  OsType(id: 'msdos', family: 'dos', name: 'MS-DOS 6.22', badge: 'DOS', arch: 'x86_16', cpu: '486',
      vga: 'cirrus', ram: 16, diskMb: 256, boot: 'floppy', net: false, tablet: false,
      tipTr: 'Kurulum disketi (.img) ile açılır', tipEn: 'Boots from a setup floppy (.img)'),
  OsType(id: 'dos_other', family: 'dos', name: 'DOS (diğer)', badge: 'DOS', arch: 'x86_16', cpu: '486',
      vga: 'cirrus', ram: 16, diskMb: 256, net: false, tablet: false),

  // ------------------------------------------------------------ BSD
  OsType(id: 'freebsd', family: 'bsd', name: 'FreeBSD (64-bit)', badge: 'FBS', arch: 'x86_64', ram: 1024,
      cpus: 2, diskMb: 16384),
  OsType(id: 'openbsd', family: 'bsd', name: 'OpenBSD (64-bit)', badge: 'OBS', arch: 'x86_64', ram: 512,
      cpus: 1, diskMb: 8192),
  OsType(id: 'netbsd', family: 'bsd', name: 'NetBSD (64-bit)', badge: 'NBS', arch: 'x86_64', ram: 512, cpus: 1,
      diskMb: 8192),

  // ------------------------------------------------------------ Diğer
  OsType(id: 'reactos', family: 'other', name: 'ReactOS', badge: 'RE', arch: 'x86_32', cpu: 'pentium3',
      vga: 'std', nic: 'ne2k_pci', ram: 512, diskMb: 8192,
      tipTr: 'Açık kaynak Windows uyumlu sistem', tipEn: 'Open-source Windows-compatible OS'),
  OsType(id: 'haiku', family: 'other', name: 'Haiku (64-bit)', badge: 'HK', arch: 'x86_64', ram: 1024, cpus: 2,
      diskMb: 16384),
  OsType(id: 'kolibri', family: 'other', name: 'KolibriOS', badge: 'KO', arch: 'x86_32', cpu: 'pentium3',
      ram: 128, diskMb: 0, tipTr: 'Tamamen ISO/disketten çalışır, disk gerekmez',
      tipEn: 'Runs entirely from ISO/floppy, no disk needed'),
  OsType(id: 'other16', family: 'other', name: 'Diğer / Bilinmeyen (16-bit)', badge: '16', arch: 'x86_16',
      cpu: '486', vga: 'cirrus', ram: 16, diskMb: 256, net: false, tablet: false),
  OsType(id: 'other32', family: 'other', name: 'Diğer / Bilinmeyen (32-bit)', badge: '32', arch: 'x86_32',
      cpu: 'pentium3', ram: 512, diskMb: 8192),
  OsType(id: 'custom', family: 'other', name: 'Diğer / Bilinmeyen (64-bit)', badge: '64', arch: 'x86_64',
      ram: 1024, cpus: 2, diskMb: 16384),
];

/// Eski sürümlerdeki şablon adları.
const _legacy = {'win7_64': 'win7', 'other64': 'custom'};

OsType osById(String id) {
  final key = _legacy[id] ?? id;
  return osCatalog.firstWhere((o) => o.id == key, orElse: () => osCatalog.last);
}

List<OsType> osOfFamily(String family) => osCatalog.where((o) => o.family == family).toList();

/// VirtualBox gibi: VM adından veya ISO dosya adından sistemi tahmin eder.
OsType? detectOs(String text) {
  final s = text.toLowerCase();
  if (s.trim().isEmpty) return null;
  final is32 = RegExp(r'(i[3-6]86|x86(?![_-]?64)|x32|32[ -]?bit|\b32\b)').hasMatch(s);
  bool has(String pattern) => RegExp(pattern).hasMatch(s);

  if (has(r'win(dows)?[ _.-]*11')) return osById('win11');
  if (has(r'win(dows)?[ _.-]*10')) return osById(is32 ? 'win10_32' : 'win10');
  if (has(r'win(dows)?[ _.-]*8')) return osById('win8');
  if (has(r'win(dows)?[ _.-]*7|\bseven\b')) return osById(is32 ? 'win7_32' : 'win7');
  if (has(r'vista')) return osById('winvista');
  if (has(r'(\bxp\b|winxp|windows[ _.-]*xp|_xp_|-xp-)')) return osById('winxp');
  if (has(r'(win(dows)?[ _.-]*2000|win2k|\bw2k\b)')) return osById('win2k');
  if (has(r'(win(dows)?[ _.-]*me\b|millennium)')) return osById('winme');
  if (has(r'win(dows)?[ _.-]*98|\bw98\b')) return osById('win98');
  if (has(r'win(dows)?[ _.-]*95|\bw95\b')) return osById('win95');
  if (has(r'win(dows)?[ _.-]*3\.?1?\b|wfw')) return osById('win31');
  if (has(r'(freedos|fdbasecd|fdfullcd|fd1[0-9]|fd14)')) return osById('freedos');
  if (has(r'(ms[ _-]?dos|\bdos[ _-]?6|dos622)')) return osById('msdos');
  if (has(r'\bdos\b')) return osById('dos_other');
  if (has(r'reactos')) return osById('reactos');
  if (has(r'alpine')) return osById('alpine');
  if (has(r'debian')) return osById(is32 ? 'debian32' : 'debian');
  if (has(r'(ubuntu|kubuntu|xubuntu|lubuntu)')) return osById('ubuntu');
  if (has(r'linux[ _-]?mint|\bmint\b')) return osById('mint');
  if (has(r'(archlinux|arch[ _-]linux|^arch\b|^arch[ _-]?20\d\d)')) return osById('arch');
  if (has(r'fedora')) return osById('fedora');
  if (has(r'(tinycore|tiny[ _-]core|corepure|core-current|\bcore-\d)')) return osById('tinycore');
  if (has(r'antix')) return osById('antix');
  if (has(r'freebsd')) return osById('freebsd');
  if (has(r'openbsd')) return osById('openbsd');
  if (has(r'netbsd')) return osById('netbsd');
  if (has(r'haiku')) return osById('haiku');
  if (has(r'kolibri')) return osById('kolibri');
  if (has(r'(linux|pardus|pisi|centos|rocky|alma|rhel|opensuse|suse|manjaro|endeavour|garuda|artix|kali|parrot|'
      r'tails|zorin|pop[-_ ]?os|elementary|mx[-_ ]?\d|mxlinux|peppermint|bodhi|deepin|slackware|gentoo|void|'
      r'nixos|solus|puppy|fossapup|slax|porteus|slitaz|knoppix|q4os|devuan|mageia|pclinuxos|sparky|lxle|kodachi|'
      r'whonix|android[-_ ]?x86|bliss|primeos|steamos|lakka|batocera|recalbox|clonezilla|gparted|systemrescue|'
      r'rescuezilla|hiren|lite[-_ ]?\d|vanilla|nobara|kaos|chakra|elive|trisquel|pureos|kubuntu|xubuntu|lubuntu|'
      r'ubuntu|budgie|mate|xfce|kde|gnome|cinnamon|live[-_]?cd|livecd|\bdsl\b|damn[-_ ]?small)')) {
    if (has(r'(ubuntu|zorin|pop[-_ ]?os|elementary|kubuntu|xubuntu|lubuntu|budgie)')) return osById('ubuntu');
    if (has(r'(manjaro|endeavour|garuda|artix)')) return osById('arch');
    if (has(r'(\bdsl\b|damn[-_ ]?small|puppy|slitaz|porteus|slax)')) return osById('linux32');
    return osById(is32 ? 'linux32' : 'linux64');
  }
  return null;
}

/// Dosyadan tespit sonucu: hangi sistem, neye bakılarak bulundu.
class OsDetection {
  final OsType os;
  final String source;
  const OsDetection(this.os, this.source);
}

/// VirtualBox gibi: önce dosya adına, sonra dosyanın içine bakar
/// (ISO birim etiketi, disket önyükleme kesimi).
Future<OsDetection?> detectOsFromFile(String path) async {
  final name = path.split('/').last;
  final byName = detectOs(name.replaceAll(RegExp(r'\.[^.]+$'), ''));
  if (byName != null) return OsDetection(byName, name);
  try {
    final f = await File(path).open();
    try {
      final len = await f.length();
      // ISO 9660: 16. sektörde "CD001" ve 32 baytlık birim etiketi
      if (len > 34816) {
        await f.setPosition(32768);
        final pvd = await f.read(72);
        if (pvd.length >= 72 && String.fromCharCodes(pvd.sublist(1, 6)) == 'CD001') {
          final label = String.fromCharCodes(pvd.sublist(40, 72)).trim();
          final os = _detectFromIsoLabel(label);
          if (os != null) return OsDetection(os, label);
          // Etiket bir şey söylemiyor: ISO'nun içindeki klasör ve dosyalara bak
          final byContent = await _IsoScanner(f).detect();
          if (byContent != null) return byContent;
        }
      }
      // Disket / FAT önyükleme kesimi: OEM adı (3..11) ve birim etiketi (43..54)
      if (len >= 512 && len <= 2949120) {
        await f.setPosition(0);
        final bs = await f.read(62);
        if (bs.length >= 62) {
          final oem = String.fromCharCodes(bs.sublist(3, 11)).toUpperCase();
          final vol = String.fromCharCodes(bs.sublist(43, 54)).trim();
          final os = _detectFromBootSector(oem, vol);
          if (os != null) return OsDetection(os, oem.trim());
        }
      }
    } finally {
      await f.close();
    }
  } catch (_) {}
  return null;
}

OsType? _detectFromIsoLabel(String label) {
  final l = label.toUpperCase();
  if (l.isEmpty) return null;
  final x64 = l.contains('X64') || l.contains('XFRE') || l.contains('AMD64') || l.contains('X86_64');
  // Microsoft kurulum DVD'lerinin kod adları
  if (RegExp(r'^(CCCOMA|CPBA|CENA|CCSA|CPRA|CCOMA|J_CCSA|ESD-ISO)').hasMatch(l)) {
    return osById(l.contains('X86FRE') ? 'win10_32' : 'win10');
  }
  if (RegExp(r'^(IR[0-9M]|IRM|HRM|HB1)').hasMatch(l)) return osById('win8');
  if (RegExp(r'^(GRM|GSP1RM|GRTM|GRC|7600|7601)').hasMatch(l)) return osById(x64 ? 'win7' : 'win7_32');
  if (RegExp(r'^(LRM|FB1E|FRM|LB1)').hasMatch(l)) return osById('winvista');
  if (RegExp(r'^(WX|WINXP|XP)').hasMatch(l)) return osById('winxp');
  if (RegExp(r'^(W2[PSAK]|WIN2000|W2K)').hasMatch(l)) return osById('win2k');
  if (l.contains('WINME') || l.startsWith('WME')) return osById('winme');
  if (l.contains('WIN98') || l.startsWith('W98')) return osById('win98');
  if (l.contains('WIN95') || l.startsWith('W95')) return osById('win95');
  return detectOs(label);
}

OsType? _detectFromBootSector(String oem, String vol) {
  if (oem.contains('FRDOS') || oem.contains('FREEDOS')) return osById('freedos');
  if (oem.startsWith('MSWIN4')) return osById('win98');
  if (oem.startsWith('MSDOS') || oem.startsWith('IBM')) return osById('msdos');
  return detectOs(vol);
}

/// ISO 9660 dosya sistemini okuyup içeriğe göre sistemi tahmin eder.
class _IsoScanner {
  _IsoScanner(this.f);
  final RandomAccessFile f;

  Future<Uint8List> _read(int pos, int len) async {
    await f.setPosition(pos);
    return f.read(len);
  }

  static int _u32(Uint8List b, int o) => b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

  /// Bir dizindeki girdiler: küçük harfli ad -> (lba, boyut, klasör mü)
  Future<Map<String, (int, int, bool)>> _dir(int lba, int size) async {
    final out = <String, (int, int, bool)>{};
    final data = await _read(lba * 2048, math.min(size, 128 * 1024));
    var i = 0;
    while (i < data.length) {
      final len = data[i];
      if (len == 0) {
        i = ((i ~/ 2048) + 1) * 2048; // sektör sonu dolgusu
        continue;
      }
      if (len < 34 || i + len > data.length) break;
      final nameLen = data[i + 32];
      if (i + 33 + nameLen <= data.length && nameLen > 0) {
        final nb = data.sublist(i + 33, i + 33 + nameLen);
        if (!(nameLen == 1 && (nb[0] == 0 || nb[0] == 1))) {
          var name = String.fromCharCodes(nb).split(';').first.toLowerCase();
          if (name.endsWith('.')) name = name.substring(0, name.length - 1);
          out[name] = (_u32(data, i + 2), _u32(data, i + 10), (data[i + 25] & 2) != 0);
        }
      }
      i += len;
    }
    return out;
  }

  Future<OsDetection?> detect() async {
    try {
      final pvd = await _read(32768, 2048);
      final root = await _dir(_u32(pvd, 156 + 2), _u32(pvd, 156 + 10));
      if (root.isEmpty) return null;
      final names = <String>{...root.keys};

      Future<Map<String, (int, int, bool)>> sub(String n) async {
        final e = root[n];
        if (e == null || !e.$3) return {};
        final d = await _dir(e.$1, e.$2);
        names.addAll(d.keys);
        return d;
      }

      // 1) Debian/Ubuntu tabanlılar: .disk/info dosyasında tam ad yazar ("Pardus 23.1 ...", "Linux Mint 21 ...")
      for (final dn in ['.disk', '_disk', 'disk']) {
        final d = await sub(dn);
        final info = d['info'];
        if (info != null && !info.$3) {
          final txt = String.fromCharCodes(await _read(info.$1 * 2048, math.min(info.$2, 512))).trim();
          final title = txt.split('\n').first.trim();
          final ubuntuBased = root.containsKey('casper') || RegExp(r'ubuntu|mint|zorin|pop|elementary', caseSensitive: false).hasMatch(txt);
          var os = detectOs(txt);
          // Tanınan ama genel "Linux" çıkan dağıtımlarda tabanın profilini kullan
          if (os == null || os.id == 'linux64' || os.id == 'linux32') {
            final is32 = _is32(txt) && !_is64(txt);
            os = osById(ubuntuBased ? 'ubuntu' : (is32 ? 'debian32' : 'debian'));
          }
          final base = ubuntuBased ? t('Ubuntu tabanlı', 'Ubuntu based') : t('Debian tabanlı', 'Debian based');
          return OsDetection(os, '$title · $base');
        }
      }

      // 2) Windows kurulum diskleri (Vista ve sonrası): EFI klasöründe bootx64.efi varsa 64-bit
      if (root.containsKey('sources') && (root.containsKey('bootmgr') || root.containsKey('setup.exe'))) {
        var x64 = false;
        final efi = await sub('efi');
        final boot = efi['boot'];
        if (boot != null && boot.$3) {
          x64 = (await _dir(boot.$1, boot.$2)).containsKey('bootx64.efi');
        }
        return OsDetection(osById(x64 ? 'win10' : 'win10_32'), 'Windows Setup (${x64 ? '64' : '32'}-bit)');
      }
      if (root.containsKey('i386') && names.any((n) => n.startsWith('win51'))) return OsDetection(osById('winxp'), 'WIN51');
      if (root.containsKey('win98') || root.containsKey('win9x')) return OsDetection(osById('win98'), 'WIN98');
      if (root.containsKey('win95')) return OsDetection(osById('win95'), 'WIN95');
      if (root.containsKey('freedos')) return OsDetection(osById('freedos'), 'FREEDOS');

      // 3) Linux: önyükleyici ve çekirdek klasörlerine bak
      for (final dn in ['boot', 'isolinux', 'syslinux', 'casper', 'live', 'arch', 'liveos', 'images', 'install', 'install.amd', 'install.386', 'install_amd', 'install_386']) {
        await sub(dn);
      }
      final all = names.join(' ');
      final linuxy = RegExp(r'(isolinux|syslinux|casper|\blive\b|vmlinuz|initrd|bzimage|grub|liveos|\barch\b|'
              r'core\.gz|tinycore|apks|antix|kernel|pmagic|sysrcd|boot\.cat)')
          .hasMatch(all);
      if (!linuxy) return null;
      final is32only = _is32(all) && !_is64(all);
      if (root.containsKey('apks')) return OsDetection(osById('alpine'), t('Alpine tabanlı', 'Alpine based'));
      if (root.containsKey('casper')) return OsDetection(osById('ubuntu'), t('Ubuntu tabanlı', 'Ubuntu based'));
      if (root.containsKey('arch')) return OsDetection(osById('arch'), t('Arch tabanlı', 'Arch based'));
      if (root.containsKey('liveos') || (root.containsKey('images') && names.contains('install.img'))) {
        return OsDetection(osById('fedora'), t('Fedora / Red Hat tabanlı', 'Fedora / Red Hat based'));
      }
      final deb32 = root.containsKey('install.386') || root.containsKey('install_386');
      if (root.containsKey('live') || root.containsKey('install.amd') || root.containsKey('install_amd') || deb32) {
        return OsDetection(osById(is32only || deb32 ? 'debian32' : 'debian'),
            t('Debian tabanlı', 'Debian based'));
      }
      if (root.containsKey('antix')) return OsDetection(osById('antix'), 'antiX');
      if (names.contains('core.gz') || names.contains('tinycore.gz')) return OsDetection(osById('tinycore'), 'Tiny Core');
      if (names.contains('loader') && root.containsKey('rescue')) return OsDetection(osById('freebsd'), 'FreeBSD');
      return OsDetection(osById(is32only ? 'linux32' : 'linux64'), t('Linux (genel)', 'Linux (generic)'));
    } catch (_) {
      return null;
    }
  }

  static bool _is64(String s) => RegExp(r'(x86_64|amd64|x64|vmlinuz64|64[-_ ]?bit|efi)').hasMatch(s.toLowerCase());
  static bool _is32(String s) => RegExp(r'(i[3-6]86|x86(?!_64)|32[-_ ]?bit)').hasMatch(s.toLowerCase());
}
