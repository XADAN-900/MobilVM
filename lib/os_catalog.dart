import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'inspector.dart';
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
  OsFamily('macos', 'Klasik Mac OS (68k / PowerPC)', 'Classic Mac OS (68k / PowerPC)', Icons.laptop_mac_rounded),
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
  final bool uefi;
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
    this.uefi = false,
    this.tipTr = '',
    this.tipEn = '',
  });

  String get tip => tipEn.isEmpty ? '' : t(tipTr, tipEn);
  OsFamily get fam => familyById(family);

  /// Seçili dilde görünen ad (özel adlar aynı kalır, "Other / Unknown" gibi genel adlar çevrilir).
  String get label => tx(name);

  /// Bu sürüm için önerilen ayarlarla yeni bir VM.
  VmConfig create() => applyTo(VmConfig(
        name: label,
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
    ..tablet = tablet
    ..sound = 'auto'
    ..clipboard = clipboardDefault
    ..diskBus = fastDisk ? 'virtio' : 'ide'
    ..firmware = id == 'win11' || uefi ? 'uefi' : 'bios';

  /// Yeni 64-bit Linux/BSD kurulumları hızlı virtio diske kurulur (çekirdekleri sürücüyü içerir).
  bool get fastDisk => arch == 'x86_64' && (family == 'linux' || family == 'bsd');

  /// Pano aygıtı (virtio-serial) eski sistemlerde "bilinmeyen aygıt" sorar; onlarda kapalı başlar.
  bool get clipboardDefault =>
      family != 'dos' &&
      family != 'macos' &&
      !legacySoundTemplates.contains(id) &&
      !const {'win2k', 'winxp', 'winnt4', 'win2003', 'winxp64', 'os2', 'arcaos', 'beos', 'templeos', 'menuetos', 'kolibri', 'reactos'}
          .contains(id);
}

const osCatalog = <OsType>[
  // ------------------------------------------------------------ Windows
  OsType(id: 'win31', family: 'windows', name: 'Windows 3.1', badge: '3.1', arch: 'x86_16', cpu: '486',
      vga: 'cirrus', ram: 32, diskMb: 256, net: false, tablet: false,
      tipTr: 'Önce MS-DOS kur, sonra Windows 3.1 disketlerini çalıştır',
      tipEn: 'Install MS-DOS first, then run the Windows 3.1 floppies'),
  OsType(id: 'win1', family: 'windows', name: 'Windows 1.0', badge: '1.0', arch: 'x86_16', cpu: '486',
      vga: 'cirrus', ram: 16, diskMb: 128, boot: 'floppy', net: false, tablet: false,
      tipTr: 'Önce DOS kur, sonra Windows disketlerini çalıştır', tipEn: 'Install DOS first, then run the Windows floppies'),
  OsType(id: 'win2', family: 'windows', name: 'Windows 2.x / 386', badge: '2.0', arch: 'x86_16', cpu: '486',
      vga: 'cirrus', ram: 16, diskMb: 128, boot: 'floppy', net: false, tablet: false,
      tipTr: 'Önce DOS kur, sonra Windows disketlerini çalıştır', tipEn: 'Install DOS first, then run the Windows floppies'),
  OsType(id: 'win95', family: 'windows', name: 'Windows 95', badge: '95', arch: 'x86_32', cpu: 'pentium',
      vga: 'cirrus', nic: 'ne2k_pci', ram: 64, diskMb: 1024, tablet: false,
      tipTr: 'Touchpad fare modu önerilir', tipEn: 'Trackpad mouse mode recommended'),
  OsType(id: 'win98', family: 'windows', name: 'Windows 98', badge: '98', arch: 'x86_32', cpu: 'pentium2',
      vga: 'cirrus', nic: 'pcnet', ram: 256, diskMb: 4096, tablet: false,
      tipTr: '512 MB üstü RAM verme. Touchpad modu önerilir', tipEn: 'Do not exceed 512 MB RAM. Trackpad mode recommended'),
  OsType(id: 'winme', family: 'windows', name: 'Windows ME', badge: 'ME', arch: 'x86_32', cpu: 'pentium2',
      vga: 'cirrus', nic: 'pcnet', ram: 256, diskMb: 4096, tablet: false),
  OsType(id: 'winnt4', family: 'windows', name: 'Windows NT 4.0', badge: 'NT', arch: 'x86_32', cpu: 'pentium',
      vga: 'cirrus', nic: 'ne2k_pci', ram: 128, diskMb: 4096, tablet: false,
      tipTr: 'Disk 2 GB üstünde olmasın (NT 4 kurulum sınırı)', tipEn: 'Keep the disk under 2 GB (NT 4 setup limit)'),
  OsType(id: 'win2k', family: 'windows', name: 'Windows 2000', badge: '2K', arch: 'x86_32', cpu: 'pentium3',
      vga: 'cirrus', nic: 'rtl8139', ram: 512, diskMb: 8192),
  OsType(id: 'winxp', family: 'windows', name: 'Windows XP', badge: 'XP', arch: 'x86_32', cpu: 'pentium3',
      vga: 'cirrus', nic: 'rtl8139', ram: 512, cpus: 1, diskMb: 10240,
      tipTr: 'Telefonda en dengeli Windows', tipEn: 'The most balanced Windows on a phone'),
  OsType(id: 'winxp64', family: 'windows', name: 'Windows XP (64-bit)', badge: 'XP', arch: 'x86_64',
      vga: 'cirrus', nic: 'rtl8139', ram: 1024, cpus: 1, diskMb: 16384),
  OsType(id: 'win2003', family: 'windows', name: 'Windows Server 2003', badge: '03', arch: 'x86_32', cpu: 'pentium3',
      vga: 'cirrus', nic: 'rtl8139', ram: 512, diskMb: 10240),
  OsType(id: 'winvista', family: 'windows', name: 'Windows Vista', badge: 'VI', arch: 'x86_32', ram: 1024,
      cpus: 2, diskMb: 20480, heavy: true),
  OsType(id: 'winvista64', family: 'windows', name: 'Windows Vista (64-bit)', badge: 'VI', arch: 'x86_64',
      ram: 2048, cpus: 2, diskMb: 25600, heavy: true),
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
  OsType(id: 'win2008', family: 'windows', name: 'Windows Server 2008 R2', badge: '08', arch: 'x86_64', ram: 2048,
      cpus: 2, diskMb: 32768, heavy: true),
  OsType(id: 'win2012', family: 'windows', name: 'Windows Server 2012 R2', badge: '12', arch: 'x86_64', ram: 2048,
      cpus: 2, diskMb: 32768, heavy: true),
  OsType(id: 'win2016', family: 'windows', name: 'Windows Server 2016', badge: '16', arch: 'x86_64', ram: 2048,
      cpus: 2, diskMb: 40960, heavy: true),
  OsType(id: 'win2019', family: 'windows', name: 'Windows Server 2019', badge: '19', arch: 'x86_64', ram: 3072,
      cpus: 2, diskMb: 40960, heavy: true),
  OsType(id: 'win2022', family: 'windows', name: 'Windows Server 2022', badge: '22', arch: 'x86_64', ram: 4096,
      cpus: 2, diskMb: 51200, heavy: true,
      tipTr: 'Masaüstü deneyimi yerine Server Core çok daha hızlıdır', tipEn: 'Server Core is much faster than Desktop Experience'),
  OsType(id: 'win11', family: 'windows', name: 'Windows 11 (64-bit)', badge: '11', arch: 'x86_64', ram: 4096,
      cpus: 2, diskMb: 65536, heavy: true,
      tipTr: 'TPM/Güvenli Önyükleme kontrolünü atlatmak gerekir; çok yavaş çalışır',
      tipEn: 'Requires bypassing the TPM/Secure Boot check; runs very slowly'),

  // ------------------------------------------------------------ Linux
  OsType(id: 'alpine', family: 'linux', name: 'Alpine Linux', badge: 'AL', arch: 'x86_64', ram: 512, cpus: 2,
      diskMb: 4096, tipTr: 'Çok hafif. SSH için port: tcp:2222:22', tipEn: 'Very light. SSH port: tcp:2222:22'),
  OsType(id: 'debian', family: 'linux', name: 'Debian (64-bit)', badge: 'DEB', arch: 'x86_64', ram: 1024,
      cpus: 2, diskMb: 16384, tipTr: 'netinst ISO ile metin modunda kur', tipEn: 'Install the netinst ISO in text mode'),
  OsType(id: 'debian32', family: 'linux', name: 'Debian (32-bit)', badge: 'DEB', arch: 'x86_32', cpu: 'max',
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
  OsType(id: 'pardus', family: 'linux', name: 'Pardus (64-bit)', badge: 'PAR', arch: 'x86_64', ram: 2048, cpus: 2,
      diskMb: 25600, heavy: true),
  OsType(id: 'kali', family: 'linux', name: 'Kali Linux (64-bit)', badge: 'KAL', arch: 'x86_64', ram: 2048, cpus: 2,
      diskMb: 25600, heavy: true),
  OsType(id: 'manjaro', family: 'linux', name: 'Manjaro / EndeavourOS', badge: 'MJR', arch: 'x86_64', ram: 3072,
      cpus: 2, diskMb: 30720, heavy: true),
  OsType(id: 'opensuse', family: 'linux', name: 'openSUSE (64-bit)', badge: 'SUS', arch: 'x86_64', ram: 2048,
      cpus: 2, diskMb: 30720, heavy: true),
  OsType(id: 'rhel', family: 'linux', name: 'Rocky / Alma / CentOS (64-bit)', badge: 'RHL', arch: 'x86_64',
      ram: 2048, cpus: 2, diskMb: 25600, tipTr: 'Minimal kurulum seç', tipEn: 'Choose the minimal install'),
  OsType(id: 'slackware', family: 'linux', name: 'Slackware (64-bit)', badge: 'SLK', arch: 'x86_64', ram: 1024,
      cpus: 2, diskMb: 16384),
  OsType(id: 'gentoo', family: 'linux', name: 'Gentoo (64-bit)', badge: 'GEN', arch: 'x86_64', ram: 1024, cpus: 2,
      diskMb: 20480),
  OsType(id: 'voidlinux', family: 'linux', name: 'Void Linux (64-bit)', badge: 'VOI', arch: 'x86_64', ram: 1024,
      cpus: 2, diskMb: 8192),
  OsType(id: 'puppy', family: 'linux', name: 'Puppy Linux', badge: 'PUP', arch: 'x86_32', cpu: 'max', ram: 512,
      diskMb: 4096, tipTr: 'Tamamen RAM\'de çalışır, hızlıdır', tipEn: 'Runs entirely in RAM, fast'),
  OsType(id: 'dsl', family: 'linux', name: 'Damn Small Linux', badge: 'DSL', arch: 'x86_32', cpu: 'pentium',
      vga: 'cirrus', ram: 128, diskMb: 1024),
  OsType(id: 'android_x86', family: 'linux', name: 'Android-x86 / Bliss / PrimeOS', badge: 'AND', arch: 'x86_64',
      ram: 3072, cpus: 2, diskMb: 16384, heavy: true,
      tipTr: 'Kurulum menüsünde "nomodeset" ile açmayı dene', tipEn: 'Try booting with "nomodeset" from the boot menu'),
  OsType(id: 'chromeos', family: 'linux', name: 'ChromeOS Flex', badge: 'CRO', arch: 'x86_64', ram: 4096, cpus: 2,
      diskMb: 32768, heavy: true, uefi: true),
  OsType(id: 'tinycore', family: 'linux', name: 'Tiny Core Linux', badge: 'TC', arch: 'x86_32', cpu: 'pentium3',
      ram: 256, diskMb: 1024, tipTr: '~20 MB, saniyeler içinde açılır', tipEn: '~20 MB, boots in seconds'),
  OsType(id: 'antix', family: 'linux', name: 'antiX (32-bit)', badge: 'AX', arch: 'x86_32', cpu: 'max',
      ram: 512, diskMb: 8192),
  OsType(id: 'linux32', family: 'linux', name: 'Linux (32-bit, other)', badge: 'L32', arch: 'x86_32',
      cpu: 'max', ram: 512, diskMb: 8192),
  OsType(id: 'linux64', family: 'linux', name: 'Linux (64-bit, other)', badge: 'L64', arch: 'x86_64', ram: 1024,
      cpus: 2, diskMb: 16384),

  // ------------------------------------------------------------ DOS
  OsType(id: 'freedos', family: 'dos', name: 'FreeDOS', badge: 'FD', arch: 'x86_16', cpu: '486', vga: 'cirrus',
      ram: 32, diskMb: 512, net: false, tablet: false,
      tipTr: 'Ücretsiz ve modern DOS; eski oyunlar için ideal', tipEn: 'Free modern DOS; ideal for old games'),
  OsType(id: 'msdos', family: 'dos', name: 'MS-DOS 6.22', badge: 'DOS', arch: 'x86_16', cpu: '486',
      vga: 'cirrus', ram: 16, diskMb: 256, boot: 'floppy', net: false, tablet: false,
      tipTr: 'Kurulum disketi (.img) ile açılır', tipEn: 'Boots from a setup floppy (.img)'),
  OsType(id: 'drdos', family: 'dos', name: 'DR-DOS / OpenDOS', badge: 'DR', arch: 'x86_16', cpu: '486',
      vga: 'cirrus', ram: 16, diskMb: 256, boot: 'floppy', net: false, tablet: false),
  OsType(id: 'pcdos', family: 'dos', name: 'PC DOS (IBM)', badge: 'PC', arch: 'x86_16', cpu: '486', vga: 'cirrus',
      ram: 16, diskMb: 256, boot: 'floppy', net: false, tablet: false),
  OsType(id: 'dos_other', family: 'dos', name: 'DOS (other)', badge: 'DOS', arch: 'x86_16', cpu: '486',
      vga: 'cirrus', ram: 16, diskMb: 256, net: false, tablet: false),

  // ------------------------------------------------------------ BSD
  OsType(id: 'freebsd', family: 'bsd', name: 'FreeBSD (64-bit)', badge: 'FBS', arch: 'x86_64', ram: 1024,
      cpus: 2, diskMb: 16384),
  OsType(id: 'openbsd', family: 'bsd', name: 'OpenBSD (64-bit)', badge: 'OBS', arch: 'x86_64', ram: 512,
      cpus: 1, diskMb: 8192),
  OsType(id: 'netbsd', family: 'bsd', name: 'NetBSD (64-bit)', badge: 'NBS', arch: 'x86_64', ram: 512, cpus: 1,
      diskMb: 8192),
  OsType(id: 'freebsd32', family: 'bsd', name: 'FreeBSD (32-bit)', badge: 'FBS', arch: 'x86_32', cpu: 'pentium3',
      ram: 512, diskMb: 8192),
  OsType(id: 'openbsd32', family: 'bsd', name: 'OpenBSD (32-bit)', badge: 'OBS', arch: 'x86_32', cpu: 'pentium3',
      ram: 256, diskMb: 4096),
  OsType(id: 'netbsd32', family: 'bsd', name: 'NetBSD (32-bit)', badge: 'NBS', arch: 'x86_32', cpu: 'pentium3',
      ram: 256, diskMb: 4096),
  OsType(id: 'dragonfly', family: 'bsd', name: 'DragonFly BSD', badge: 'DFY', arch: 'x86_64', ram: 1024, cpus: 2,
      diskMb: 16384),
  OsType(id: 'ghostbsd', family: 'bsd', name: 'GhostBSD', badge: 'GHO', arch: 'x86_64', ram: 2048, cpus: 2,
      diskMb: 20480, heavy: true),

  // ------------------------------------------------------------ ARM / RISC-V / POWER Linux
  OsType(id: 'debian_arm64', family: 'linux', name: 'Debian (ARM 64)', badge: 'DEB', arch: 'arm64', ram: 1024,
      cpus: 2, diskMb: 16384, tipTr: 'arm64 netinst ISO\'su ile kur', tipEn: 'Install with the arm64 netinst ISO'),
  OsType(id: 'ubuntu_arm64', family: 'linux', name: 'Ubuntu Server (ARM 64)', badge: 'UB', arch: 'arm64',
      ram: 2048, cpus: 2, diskMb: 20480),
  OsType(id: 'alpine_arm64', family: 'linux', name: 'Alpine Linux (ARM 64)', badge: 'AL', arch: 'arm64',
      ram: 512, cpus: 2, diskMb: 4096),
  OsType(id: 'fedora_arm64', family: 'linux', name: 'Fedora (ARM 64)', badge: 'FED', arch: 'arm64', ram: 2048,
      cpus: 2, diskMb: 20480, heavy: true),
  OsType(id: 'linux_arm64', family: 'linux', name: 'Linux (ARM 64, other)', badge: 'A64', arch: 'arm64',
      ram: 1024, cpus: 2, diskMb: 16384),
  OsType(id: 'debian_armhf', family: 'linux', name: 'Debian (ARM 32)', badge: 'DEB', arch: 'arm32', ram: 512,
      cpus: 2, diskMb: 8192),
  OsType(id: 'linux_arm32', family: 'linux', name: 'Linux (ARM 32, other)', badge: 'A32', arch: 'arm32',
      ram: 512, cpus: 2, diskMb: 8192),
  OsType(id: 'debian_riscv64', family: 'linux', name: 'Debian (RISC-V 64)', badge: 'DEB', arch: 'riscv64',
      ram: 1024, cpus: 2, diskMb: 16384),
  OsType(id: 'ubuntu_riscv64', family: 'linux', name: 'Ubuntu Server (RISC-V 64)', badge: 'UB', arch: 'riscv64',
      ram: 2048, cpus: 2, diskMb: 20480),
  OsType(id: 'linux_riscv64', family: 'linux', name: 'Linux (RISC-V 64, other)', badge: 'RV', arch: 'riscv64',
      ram: 1024, cpus: 2, diskMb: 16384),
  OsType(id: 'debian_ppc64', family: 'linux', name: 'Debian (ppc64el)', badge: 'DEB', arch: 'ppc64', ram: 1024,
      cpus: 2, diskMb: 16384),
  OsType(id: 'ubuntu_ppc64', family: 'linux', name: 'Ubuntu Server (ppc64el)', badge: 'UB', arch: 'ppc64',
      ram: 2048, cpus: 2, diskMb: 20480),
  OsType(id: 'debian_ppc', family: 'linux', name: 'Debian (PowerPC 32)', badge: 'DEB', arch: 'ppc', ram: 512,
      diskMb: 8192),
  OsType(id: 'linux_ppc', family: 'linux', name: 'Linux (PowerPC, other)', badge: 'PPC', arch: 'ppc', ram: 512,
      diskMb: 8192),
  OsType(id: 'debian_m68k', family: 'linux', name: 'Debian (68k)', badge: 'DEB', arch: 'm68k', machine: 'q800',
      ram: 256, diskMb: 4096,
      tipTr: 'Çekirdek ve initrd CD\'den alınır (Gelişmiş açılış → CD\'den al)',
      tipEn: 'Kernel and initrd are taken from the CD (Advanced boot → Get from CD)'),
  OsType(id: 'linux_m68k', family: 'linux', name: 'Linux (68k, other)', badge: '68K', arch: 'm68k', machine: 'q800',
      ram: 256, diskMb: 4096),

  // ------------------------------------------------------------ Mac OS (PowerPC)
  OsType(id: 'macos7', family: 'macos', name: 'System 7.1 – Mac OS 7.6 (68k)', badge: '7', arch: 'm68k',
      machine: 'q800', ram: 128, diskMb: 1024,
      tipTr: 'Quadra 800 ROM dosyası gerekir (Gelişmiş açılış → BIOS / ROM)',
      tipEn: 'Needs a Quadra 800 ROM file (Advanced boot → BIOS / ROM)'),
  OsType(id: 'macos8_68k', family: 'macos', name: 'Mac OS 8.0 – 8.1 (68k)', badge: '8', arch: 'm68k',
      machine: 'q800', ram: 256, diskMb: 2048,
      tipTr: 'Quadra 800 ROM dosyası gerekir (Gelişmiş açılış → BIOS / ROM)',
      tipEn: 'Needs a Quadra 800 ROM file (Advanced boot → BIOS / ROM)'),
  OsType(id: 'macos9', family: 'macos', name: 'Mac OS 9.2', badge: 'OS9', arch: 'ppc', ram: 512, diskMb: 4096,
      tipTr: 'Kurulum CD\'sinden açılır; diski önce Drive Setup ile biçimlendir',
      tipEn: 'Boots from the install CD; format the disk with Drive Setup first'),
  OsType(id: 'macosx103', family: 'macos', name: 'Mac OS X 10.3 Panther', badge: '10.3', arch: 'ppc', ram: 768,
      diskMb: 12288, heavy: true),
  OsType(id: 'macosx104', family: 'macos', name: 'Mac OS X 10.4 Tiger', badge: '10.4', arch: 'ppc', ram: 1024,
      diskMb: 20480, heavy: true, tipTr: 'Diski önce Disk İzlencesi ile Mac OS Genişletilmiş olarak biçimlendir',
      tipEn: 'Format the disk as Mac OS Extended with Disk Utility first'),
  OsType(id: 'macosx105', family: 'macos', name: 'Mac OS X 10.5 Leopard', badge: '10.5', arch: 'ppc', ram: 1536,
      diskMb: 20480, heavy: true),

  // ------------------------------------------------------------ BSD (diğer mimariler)
  OsType(id: 'freebsd_arm64', family: 'bsd', name: 'FreeBSD (ARM 64)', badge: 'FBS', arch: 'arm64', ram: 1024,
      cpus: 2, diskMb: 16384),

  // ------------------------------------------------------------ Diğer
  OsType(id: 'reactos', family: 'other', name: 'ReactOS', badge: 'RE', arch: 'x86_32', cpu: 'pentium3',
      vga: 'std', nic: 'ne2k_pci', ram: 512, diskMb: 8192,
      tipTr: 'Açık kaynak Windows uyumlu sistem', tipEn: 'Open-source Windows-compatible OS'),
  OsType(id: 'haiku', family: 'other', name: 'Haiku (64-bit)', badge: 'HK', arch: 'x86_64', ram: 1024, cpus: 2,
      diskMb: 16384),
  OsType(id: 'kolibri', family: 'other', name: 'KolibriOS', badge: 'KO', arch: 'x86_32', cpu: 'pentium3',
      ram: 128, diskMb: 0, tipTr: 'Tamamen ISO/disketten çalışır, disk gerekmez',
      tipEn: 'Runs entirely from ISO/floppy, no disk needed'),
  OsType(id: 'os2', family: 'other', name: 'OS/2 Warp 3 / 4', badge: 'OS2', arch: 'x86_32', cpu: 'pentium',
      vga: 'std', nic: 'pcnet', ram: 64, diskMb: 2048, tablet: false),
  OsType(id: 'arcaos', family: 'other', name: 'ArcaOS / eComStation', badge: 'ARC', arch: 'x86_32', cpu: 'pentium3',
      vga: 'std', nic: 'e1000', ram: 1024, diskMb: 8192),
  OsType(id: 'beos', family: 'other', name: 'BeOS R5 / Zeta', badge: 'BE', arch: 'x86_32', cpu: 'pentium2',
      vga: 'std', nic: 'ne2k_pci', ram: 256, diskMb: 2048, tablet: false),
  OsType(id: 'solaris', family: 'other', name: 'Oracle Solaris (x86)', badge: 'SOL', arch: 'x86_64', ram: 2048,
      cpus: 2, diskMb: 25600, heavy: true),
  OsType(id: 'openindiana', family: 'other', name: 'OpenIndiana / illumos', badge: 'OI', arch: 'x86_64', ram: 2048,
      cpus: 2, diskMb: 20480, heavy: true),
  OsType(id: 'minix', family: 'other', name: 'MINIX 3', badge: 'MNX', arch: 'x86_32', cpu: 'pentium3', ram: 256,
      diskMb: 2048, tablet: false),
  OsType(id: 'plan9', family: 'other', name: 'Plan 9 / 9front', badge: '9', arch: 'x86_64', ram: 512, diskMb: 4096,
      tablet: false),
  OsType(id: 'qnx', family: 'other', name: 'QNX', badge: 'QNX', arch: 'x86_32', cpu: 'pentium3', ram: 256,
      diskMb: 2048, tablet: false),
  OsType(id: 'serenity', family: 'other', name: 'SerenityOS', badge: 'SER', arch: 'x86_64', ram: 1024, cpus: 2,
      diskMb: 4096),
  OsType(id: 'redox', family: 'other', name: 'Redox OS', badge: 'RDX', arch: 'x86_64', ram: 2048, cpus: 2,
      diskMb: 4096),
  OsType(id: 'templeos', family: 'other', name: 'TempleOS / ZealOS', badge: 'TOS', arch: 'x86_64', vga: 'std',
      ram: 512, diskMb: 2048, net: false, tablet: false),
  OsType(id: 'menuetos', family: 'other', name: 'MenuetOS', badge: 'MEN', arch: 'x86_64', ram: 256, diskMb: 0,
      net: false, tablet: false, boot: 'floppy',
      tipTr: 'Disket imajından açılır', tipEn: 'Boots from the floppy image'),
  OsType(id: 'aros', family: 'other', name: 'AROS / Icaros Desktop', badge: 'ARO', arch: 'x86_32', cpu: 'pentium3',
      ram: 512, diskMb: 4096, tablet: false),
  OsType(id: 'other16', family: 'other', name: 'Other / Unknown (16-bit)', badge: '16', arch: 'x86_16',
      cpu: '486', vga: 'cirrus', ram: 16, diskMb: 256, net: false, tablet: false),
  OsType(id: 'other32', family: 'other', name: 'Other / Unknown (32-bit)', badge: '32', arch: 'x86_32',
      cpu: 'pentium3', ram: 512, diskMb: 8192),
  OsType(id: 'other_arm64', family: 'other', name: 'Other / Unknown (ARM 64)', badge: 'A64', arch: 'arm64',
      ram: 256, cpus: 1, diskMb: 0, net: false),
  OsType(id: 'other_arm32', family: 'other', name: 'Other / Unknown (ARM 32)', badge: 'A32', arch: 'arm32',
      ram: 256, cpus: 1, diskMb: 0, net: false),
  OsType(id: 'other_ppc', family: 'other', name: 'Other / Unknown (PowerPC 32)', badge: 'PPC', arch: 'ppc',
      ram: 256, diskMb: 0, net: false),
  OsType(id: 'other_ppc64', family: 'other', name: 'Other / Unknown (PowerPC 64)', badge: 'P64', arch: 'ppc64',
      ram: 512, diskMb: 0, net: false),
  OsType(id: 'other_m68k', family: 'other', name: 'Other / Unknown (68k)', badge: '68K', arch: 'm68k',
      machine: 'q800', ram: 128, diskMb: 0, net: false),
  OsType(id: 'other_riscv64', family: 'other', name: 'Other / Unknown (RISC-V 64)', badge: 'RV', arch: 'riscv64',
      ram: 256, cpus: 1, diskMb: 0, net: false),
  OsType(id: 'custom', family: 'other', name: 'Other / Unknown (64-bit)', badge: '64', arch: 'x86_64',
      ram: 1024, cpus: 2, diskMb: 16384),
];

/// Eski sürümlerdeki şablon adları.
const _legacy = {'win7_64': 'win7', 'other64': 'custom'};

OsType osById(String id) {
  final key = _legacy[id] ?? id;
  return osCatalog.firstWhere((o) => o.id == key, orElse: () => osCatalog.last);
}

List<OsType> osOfFamily(String family) => osCatalog.where((o) => o.family == family).toList();

/// Metindeki mimari ipucu: arm64, arm32, ppc64, ppc, riscv64, m68k ya da null (x86 / bilinmiyor).
String? archHintOf(String text) {
  final s = text.toLowerCase();
  if (RegExp(r'(m68k|\b68k\b|mc680[234]0|680[34]0|quadra|mac68k)').hasMatch(s)) return 'm68k';
  if (RegExp(r'(aarch64|arm64|armv8)').hasMatch(s)) return 'arm64';
  if (RegExp(r'(armhf|armel|armv7|arm32|\barm\b)').hasMatch(s)) return 'arm32';
  if (RegExp(r'(ppc64el|ppc64le|ppc64|power9|power8|pseries)').hasMatch(s)) return 'ppc64';
  if (RegExp(r'(powerpc|\bppc\b|_ppc|-ppc|macppc|powermac)').hasMatch(s)) return 'ppc';
  if (RegExp(r'(riscv64|risc-v|riscv)').hasMatch(s)) return 'riscv64';
  return null;
}

/// Bir dağıtımın başka mimarideki karşılığı (ör. debian + arm64 -> Debian (ARM 64)).
OsType withArch(OsType os, String? arch) {
  if (arch == null || os.arch == arch || os.family == 'windows' || os.family == 'dos') return os;
  final base = os.id.replaceAll(RegExp(r'(32|_armhf|_arm64|_riscv64|_ppc64|_ppc|_m68k)$'), '');
  const table = {
    'debian:arm64': 'debian_arm64', 'debian:arm32': 'debian_armhf', 'debian:riscv64': 'debian_riscv64',
    'debian:ppc64': 'debian_ppc64', 'debian:ppc': 'debian_ppc',
    'ubuntu:arm64': 'ubuntu_arm64', 'ubuntu:riscv64': 'ubuntu_riscv64', 'ubuntu:ppc64': 'ubuntu_ppc64',
    'alpine:arm64': 'alpine_arm64', 'fedora:arm64': 'fedora_arm64', 'freebsd:arm64': 'freebsd_arm64',
    'debian:m68k': 'debian_m68k',
  };
  final hit = table['$base:$arch'];
  if (hit != null) return osById(hit);
  if (os.family == 'linux' || os.family == 'bsd') {
    return osById(switch (arch) {
      'arm64' => 'linux_arm64',
      'arm32' => 'linux_arm32',
      'riscv64' => 'linux_riscv64',
      'ppc' => 'linux_ppc',
      'm68k' => 'linux_m68k',
      _ => 'debian_ppc64',
    });
  }
  return osById('other_$arch');
}

/// VirtualBox gibi: VM adından veya ISO dosya adından sistemi (ve mimarisini) tahmin eder.
OsType? detectOs(String text) {
  final s = text.toLowerCase();
  if (s.trim().isEmpty) return null;
  // Klasik Mac OS: 68k (Quadra) ve PowerPC
  if (RegExp(r'(system ?7|mac ?os ?7|macos ?7|\bos ?7\.[0-6])').hasMatch(s)) return osById('macos7');
  if (RegExp(r'(mac ?os ?8(\.[01])?\b|macos ?8(\.[01])?\b)').hasMatch(s) && !RegExp(r'8\.[56]').hasMatch(s)) {
    return osById('macos8_68k');
  }
  if (RegExp(r'(mac ?os ?9|macos9|os ?9\.\d)').hasMatch(s)) return osById('macos9');
  if (RegExp(r'(panther|mac ?os ?x? ?10\.3)').hasMatch(s)) return osById('macosx103');
  if (RegExp(r'(tiger|mac ?os ?x? ?10\.4)').hasMatch(s)) return osById('macosx104');
  if (RegExp(r'(leopard|mac ?os ?x? ?10\.5)').hasMatch(s)) return osById('macosx105');
  final base = _detectBase(s);
  final hint = archHintOf(s);
  if (base == null) return hint == null ? null : osById('other_$hint');
  return withArch(base, hint);
}

OsType? _detectBase(String text) {
  final s = text.toLowerCase();
  if (s.trim().isEmpty) return null;
  final is32 = RegExp(r'(i[3-6]86|x86(?![_-]?64)|x32|32[ -]?bit|\b32\b)').hasMatch(s);
  final is64 = RegExp(r'(x64|amd64|x86[_-]64|64[ -]?bit)').hasMatch(s);
  bool has(String pattern) => RegExp(pattern).hasMatch(s);

  // Windows Server
  if (has(r'(server[^0-9]{0,15}2022|win(dows)?[ _.-]*2022|\bws2022)')) return osById('win2022');
  if (has(r'(server[^0-9]{0,15}2019|win(dows)?[ _.-]*2019)')) return osById('win2019');
  if (has(r'(server[^0-9]{0,15}2016|win(dows)?[ _.-]*2016)')) return osById('win2016');
  if (has(r'(server[^0-9]{0,15}2012|win(dows)?[ _.-]*2012)')) return osById('win2012');
  if (has(r'(server[^0-9]{0,15}2008|win(dows)?[ _.-]*2008)')) return osById('win2008');
  if (has(r'(server[^0-9]{0,15}2003|win(dows)?[ _.-]*2003|\bw2k3\b|win2k3)')) return osById('win2003');

  if (has(r'win(dows)?[ _.-]*11')) return osById('win11');
  if (has(r'win(dows)?[ _.-]*10')) return osById(is32 ? 'win10_32' : 'win10');
  if (has(r'win(dows)?[ _.-]*8')) return osById('win8');
  if (has(r'win(dows)?[ _.-]*7|\bseven\b')) return osById(is32 ? 'win7_32' : 'win7');
  if (has(r'vista')) return osById(is64 && !is32 ? 'winvista64' : 'winvista');
  if (has(r'(\bxp\b|winxp|windows[ _.-]*xp|_xp_|-xp-)')) return osById(is64 && !is32 ? 'winxp64' : 'winxp');
  if (has(r'(win(dows)?[ _.-]*2000|win2k|\bw2k\b)')) return osById('win2k');
  if (has(r'(win(dows)?[ _.-]*nt[ _.-]*4|winnt[ _.-]*4|\bnt[ _-]?4(\.0)?\b)')) return osById('winnt4');
  if (has(r'(win(dows)?[ _.-]*me\b|millennium)')) return osById('winme');
  if (has(r'win(dows)?[ _.-]*98|\bw98\b')) return osById('win98');
  if (has(r'win(dows)?[ _.-]*95|\bw95\b')) return osById('win95');
  if (has(r'win(dows)?[ _.-]*3\.?1?\b|wfw')) return osById('win31');
  if (has(r'win(dows)?[ _.-]*2\.\d|win(dows)?[ _/-]*386\b')) return osById('win2');
  if (has(r'win(dows)?[ _.-]*1\.0')) return osById('win1');
  if (has(r'(freedos|fdbasecd|fdfullcd|fd1[0-9]|fd14)')) return osById('freedos');
  if (has(r'(dr[ _-]?dos|opendos|novell[ _-]?dos)')) return osById('drdos');
  if (has(r'(pc[ _-]?dos|ibm[ _-]?dos)')) return osById('pcdos');
  if (has(r'(ms[ _-]?dos|\bdos[ _-]?6|dos622)')) return osById('msdos');
  if (has(r'\bdos\b')) return osById('dos_other');
  if (has(r'reactos')) return osById('reactos');
  if (has(r'(arcaos|ecomstation|\becs[ _-]?2)')) return osById('arcaos');
  if (has(r'(\bos[ /_-]?2\b|\bwarp[ _-]?[34]?\b)')) return osById('os2');
  if (has(r'(\bbeos\b|beos[ _-]?r\d|\bzeta\b)')) return osById('beos');
  if (has(r'(openindiana|illumos|omnios|\boi-hipster)')) return osById('openindiana');
  if (has(r'(solaris|\bsol-1[01])')) return osById('solaris');
  if (has(r'minix')) return osById('minix');
  if (has(r'(plan[ _-]?9|9front)')) return osById('plan9');
  if (has(r'\bqnx')) return osById('qnx');
  if (has(r'serenity')) return osById('serenity');
  if (has(r'redox')) return osById('redox');
  if (has(r'(templeos|temple[ _-]os|zealos)')) return osById('templeos');
  if (has(r'menuet')) return osById('menuetos');
  if (has(r'(\baros\b|icaros)')) return osById('aros');
  if (has(r'(android[-_ ]?x86|blissos|bliss[-_ ]?os|primeos|\bbliss\b)')) return osById('android_x86');
  if (has(r'(chromeos|chrome[-_ ]?os|cloudready)')) return osById('chromeos');
  if (has(r'(dragonfly)')) return osById('dragonfly');
  if (has(r'ghostbsd')) return osById('ghostbsd');
  if (has(r'alpine')) return osById('alpine');
  if (has(r'pardus')) return osById('pardus');
  if (has(r'\bkali')) return osById('kali');
  if (has(r'(manjaro|endeavour|garuda)')) return osById('manjaro');
  if (has(r'(opensuse|\bsuse|\bsles)')) return osById('opensuse');
  if (has(r'(rocky|almalinux|\balma\b|centos|\brhel)')) return osById('rhel');
  if (has(r'slackware')) return osById('slackware');
  if (has(r'gentoo')) return osById('gentoo');
  if (has(r'void[-_ ]?(linux|live)')) return osById('voidlinux');
  if (has(r'(puppy|fossapup|bookwormpup|\bpup[-_])')) return osById('puppy');
  if (has(r'(\bdsl\b|damn[-_ ]?small)')) return osById('dsl');
  if (has(r'debian')) return osById(is32 ? 'debian32' : 'debian');
  if (has(r'(ubuntu|kubuntu|xubuntu|lubuntu)')) return osById('ubuntu');
  if (has(r'linux[ _-]?mint|\bmint\b')) return osById('mint');
  if (has(r'(archlinux|arch[ _-]linux|^arch\b|^arch[ _-]?20\d\d)')) return osById('arch');
  if (has(r'fedora')) return osById('fedora');
  if (has(r'(tinycore|tiny[ _-]core|corepure|core-current|\bcore-\d)')) return osById('tinycore');
  if (has(r'antix')) return osById('antix');
  if (has(r'freebsd')) return osById(is32 && !is64 ? 'freebsd32' : 'freebsd');
  if (has(r'openbsd')) return osById(is32 && !is64 ? 'openbsd32' : 'openbsd');
  if (has(r'netbsd')) return osById(is32 && !is64 ? 'netbsd32' : 'netbsd');
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

  /// Bilinen bir dağıtım değil; içerik incelemesiyle bulunan (ör. kendi yazdığın) sistem.
  final bool custom;
  final bool uefi;
  final String? boot; // cd | floppy | disk
  final List<String> findings;

  /// Ürünün kendi adı (ör. ISO etiketi "TyrOS 1.0"); VM adı olarak kullanılır.
  final String? productName;

  /// İçerik büyüklüğüne göre önerilen en az RAM (MB), ör. büyük masaüstü canlı sistemleri.
  final int? ramHint;

  const OsDetection(this.os, this.source,
      {this.custom = false,
      this.uefi = false,
      this.boot,
      this.findings = const [],
      this.productName,
      this.ramHint});

  /// VM için önerilen ad: türetilmiş dağıtımlarda kendi adı (ör. "TyrOS 1.0"), yoksa sürüm adı.
  String get suggestedName {
    final p = productName?.trim() ?? '';
    if (p.isEmpty) return os.label;
    final key = os.name.split(RegExp(r'[ (]')).first.toLowerCase();
    if (!custom && p.toLowerCase().contains(key)) return os.label;
    return p.length > 40 ? p.substring(0, 40) : p;
  }

  OsDetection copyWith({OsType? os, String? productName, int? ramHint, List<String>? findings}) =>
      OsDetection(os ?? this.os, source,
      custom: custom,
      uefi: uefi,
      boot: boot,
      findings: findings ?? this.findings,
      productName: productName ?? this.productName,
      ramHint: ramHint ?? this.ramHint);

  /// Önerilen ayarları VM'e uygular (bilinen sürüm + içerikten gelen ek bilgiler).
  void applyTo(VmConfig v) {
    os.applyTo(v);
    v.firmware = uefi ? 'uefi' : 'bios';
    if (custom) {
      // Hobi / özel sistemlerde genelde USB ve ağ sürücüsü yoktur: PS/2 fare, ağ kapalı, az bellek
      v.tablet = false;
      v.net = false;
      v.cpus = 1;
      v.ramMb = switch (os.arch) { 'x86_16' => 16, 'x86_32' => 128, _ => 256 };
      v.vga = os.arch == 'x86_16' ? 'cirrus' : 'std';
    }
    if (boot != null) v.boot = boot!;
    if (ramHint != null && v.ramMb < ramHint!) v.ramMb = ramHint!;
  }
}

/// VirtualBox gibi: önce dosya adına, sonra dosyanın içine bakar
/// (ISO birim etiketi, disket önyükleme kesimi).
Future<OsDetection?> detectOsFromFile(String path) async {
  final name = path.split('/').last;
  final byName = detectOs(name.replaceAll(RegExp(r'\.[^.]+$'), ''));
  // Ad yalnızca mimariyi ima ediyorsa ("...-arm.iso") karar verme: önce içine bak
  if (byName != null && !byName.id.startsWith('other')) return OsDetection(byName, name);
  final fromContent = await _detectFromContent(path, name);
  return fromContent ?? (byName == null ? null : OsDetection(byName, name));
}

Future<OsDetection?> _detectFromContent(String path, String name) async {
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
          final scanner = _IsoScanner(f);
          OsDetection? result;
          final os = _detectFromIsoLabel(label);
          if (os != null) result = OsDetection(os, label);
          // ISO'nun içindeki klasör ve dosyalara bak (etiket tanıdıysa bile boyut bilgisi için taranır)
          final scanned = await scanner.detect();
          result ??= scanned;
          // Bilinen dağıtım değil: içini açıp çekirdeğe / önyükleyiciye bak
          result ??= _fromReport(await inspectIso(f, len));
          if (result == null) return null;
          // Okunabilir etiket ("TyrOS 1.0") ürün adıdır; büyük canlı sistem dosyası daha çok RAM ister
          final human = RegExp(r'[a-z]').hasMatch(label) && !RegExp(r'^(CDROM|ISOIMAGE|CD_?ROM)$', caseSensitive: false).hasMatch(label);
          final sq = scanner.squashBytes;
          int? hint;
          if (sq > 1500 << 20) {
            hint = 3072;
          } else if (sq > 700 << 20) {
            hint = 2048;
          }
          final extra = <String>[
            if (sq > 0) '${t('Canlı sistem dosyası', 'Live filesystem')}: ${(sq / (1 << 20)).round()} MB',
            if (hint != null) '${t('Önerilen RAM', 'Recommended RAM')}: ${hint ~/ 1024} GB',
          ];
          // Mimari: etiket ("arm64", "ppc64el"...) veya içerik (EFI önyükleyicisi) x86 dışı diyorsa düzelt
          final archHint = archHintOf(label) ?? scanner.archHint;
          final archOs = archHint != null && isX86Arch(result.os.arch) && result.os.family != 'windows'
              ? withArch(result.os, archHint)
              : null;
          return result.copyWith(
            os: archOs,
            productName: human ? label : (scanner.productName ?? result.productName),
            ramHint: hint,
            findings: [...result.findings, ...extra],
          );
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
      // Ham disk / disket imajı: MBR, bölüm tablosu ve önyükleme kodu
      await f.setPosition(0);
      final head = await f.read(4);
      final container = String.fromCharCodes(head);
      if (!container.startsWith('QFI') && !container.startsWith('<<<') && !container.startsWith('KDM') &&
          !container.startsWith('cone') && !container.startsWith('vhdx')) {
        return _fromReport(await inspectRaw(f, len));
      }
    } finally {
      await f.close();
    }
  } catch (_) {}
  return null;
}

OsDetection? _fromReport(MediaReport rep) {
  final findings = rep.findings;
  if (rep.linuxKernel) {
    final os = isX86Arch(rep.arch) || rep.arch.isEmpty
        ? osById(rep.arch == 'x86_32' ? 'linux32' : 'linux64')
        : withArch(osById('linux64'), rep.arch);
    return OsDetection(os, t('Linux çekirdeği', 'Linux kernel'),
        uefi: rep.uefiOnly && isX86Arch(os.arch), findings: findings);
  }
  if (rep.macHint) {
    return OsDetection(osById(rep.macHint9 ? 'macos9' : 'macosx104'), 'Apple Partition Map', findings: findings);
  }
  if (rep.windowsHint != null) {
    return OsDetection(osById('winxp'), t('NTFS bölümü', 'NTFS partition'), boot: 'disk', findings: findings);
  }
  if (rep.bsdHint != null) return OsDetection(osById(rep.bsdHint!), 'BSD', boot: 'disk', findings: findings);
  if (rep.linuxPartition) {
    return OsDetection(osById('linux64'), t('Linux bölümü', 'Linux partition'), boot: 'disk', findings: findings);
  }
  if (rep.arch.isEmpty) return null;
  final os = osById(switch (rep.arch) {
    'x86_16' => 'other16',
    'x86_32' => 'other32',
    'x86_64' => 'custom',
    _ => 'other_${rep.arch}',
  });
  return OsDetection(os, t('Özel işletim sistemi', 'Custom operating system'),
      custom: true,
      uefi: rep.uefiOnly && isX86Arch(rep.arch) && rep.arch != 'x86_16',
      boot: isX86Arch(rep.arch) ? rep.boot : 'cd',
      findings: findings);
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
  if (oem.contains('DRDOS') || oem.contains('OPENDOS')) return osById('drdos');
  if (oem.startsWith('IBM')) return osById('pcdos');
  if (oem.startsWith('MSDOS')) return osById('msdos');
  return detectOs(vol);
}

/// ISO 9660 dosya sistemini okuyup içeriğe göre sistemi tahmin eder.
class _IsoScanner {
  _IsoScanner(this.f);
  final RandomAccessFile f;

  /// En büyük canlı sistem dosyasının (squashfs) boyutu.
  int squashBytes = 0;

  /// .disk/info'dan okunan ürün adı.
  String? productName;

  /// İçerikteki dosya/klasör adlarından mimari ipucu (EFI önyükleyicileri, ppc klasörü vb.).
  String? archHint;

  Future<Uint8List> _read(int pos, int len) async {
    await f.setPosition(pos);
    return f.read(len);
  }

  static int _u32(Uint8List b, int o) => b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

  /// Bir dizindeki girdiler: küçük harfli ad -> (lba, boyut, klasör mü)
  Future<Map<String, (int, int, bool)>> _dir(int lba, int size) async {
    final data = await _read(lba * 2048, math.min(size, 128 * 1024));
    return {for (final e in parseIsoDir(data)) e.name: (e.lba, e.size, e.dir)};
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
        // Canlı sistem dosyası: adı squashfs olan ya da canlı klasörlerdeki en büyük dosya
        final liveDir = const ['live', 'casper', 'liveos', 'arch'].contains(n);
        for (final x in d.entries) {
          if (x.value.$3) continue;
          if (RegExp(r'(\.squashfs|\.sfs|squashfs\.img|\.erofs|\.squ)$').hasMatch(x.key) ||
              (liveDir && x.value.$2 > (64 << 20))) {
            squashBytes = math.max(squashBytes, x.value.$2);
          }
        }
        return d;
      }
      // canlı sistem dosyalarının boyutu için olası klasörler
      for (final dn in ['live', 'casper', 'liveos', 'arch', 'boot']) {
        await sub(dn);
      }
      // Mimari: EFI önyükleyicisinin adı en güvenilir ipucudur
      final efiDir = await sub('efi');
      final efiBoot = efiDir['boot'];
      final efiNames = efiBoot != null && efiBoot.$3 ? (await _dir(efiBoot.$1, efiBoot.$2)).keys.toSet() : <String>{};
      if (efiNames.contains('bootaa64.efi') && !efiNames.contains('bootx64.efi')) {
        archHint = 'arm64';
      } else if (efiNames.contains('bootriscv64.efi') && !efiNames.contains('bootx64.efi')) {
        archHint = 'riscv64';
      } else if (efiNames.contains('bootarm.efi') && !efiNames.contains('bootx64.efi')) {
        archHint = 'arm32';
      } else if ((root.containsKey('ppc') || root.containsKey('ppc64')) && !root.containsKey('isolinux')) {
        archHint = 'ppc64';
      }

      // 1) Debian/Ubuntu tabanlılar: .disk/info dosyasında tam ad yazar ("Pardus 23.1 ...", "Linux Mint 21 ...")
      for (final dn in ['.disk', '_disk', 'disk']) {
        final d = await sub(dn);
        final info = d['info'];
        if (info != null && !info.$3) {
          final txt = String.fromCharCodes(await _read(info.$1 * 2048, math.min(info.$2, 512))).trim();
          final title = txt.split('\n').first.trim();
          productName = title.split(RegExp(r'\s+')).take(2).join(' ');
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
      return null; // geri kalanı derin inceleme (inspector.dart) karar verir
    } catch (_) {
      return null;
    }
  }

  static bool _is64(String s) => RegExp(r'(x86_64|amd64|x64|vmlinuz64|64[-_ ]?bit|efi)').hasMatch(s.toLowerCase());
  static bool _is32(String s) => RegExp(r'(i[3-6]86|x86(?!_64)|32[-_ ]?bit)').hasMatch(s.toLowerCase());
}
