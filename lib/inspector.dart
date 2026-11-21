import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'state.dart';

/// Bir ISO / disk / disket imajının içini açıp inceleme sonucu.
/// Bilinen bir dağıtım olmasa bile (ör. kendi yazdığın işletim sistemi)
/// mimariyi, önyükleme türünü ve BIOS/UEFI ihtiyacını bulur.
class MediaReport {
  /// x86_16 | x86_32 | x86_64 | '' (bilinmiyor)
  String arch = '';
  bool uefiOnly = false;
  bool linuxKernel = false;
  bool customOs = false;
  String? windowsHint; // NTFS bölümü vb.
  String? bsdHint;
  bool linuxPartition = false;
  String boot = 'cd';
  final List<String> findings = [];
}

class _Reader {
  _Reader(this.f, this.length);
  final RandomAccessFile f;
  final int length;

  Future<Uint8List> read(int pos, int len) async {
    if (pos < 0 || pos >= length || len <= 0) return Uint8List(0);
    await f.setPosition(pos);
    return f.read(math.min(len, length - pos));
  }
}

int _u16(Uint8List b, int o) => o + 1 < b.length ? b[o] | (b[o + 1] << 8) : 0;
int _u32(Uint8List b, int o) =>
    o + 3 < b.length ? b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24) : 0;

bool _has(Uint8List h, List<int> n, [int limit = 1 << 30]) {
  final end = math.min(h.length, limit) - n.length;
  outer:
  for (var i = 0; i <= end; i++) {
    if (h[i] != n[0]) continue;
    for (var k = 1; k < n.length; k++) {
      if (h[i + k] != n[k]) continue outer;
    }
    return true;
  }
  return false;
}

/// x86 makine kodunda işlemci modu geçişlerini arar.
///  - EFER MSR'ına yazma (mov ecx, 0xC0000080) -> 64-bit uzun mod
///  - lgdt + mov cr0, eax -> 32-bit korumalı mod
String? cpuModeOf(Uint8List b) {
  if (_has(b, const [0xB9, 0x80, 0x00, 0x00, 0xC0])) return 'x86_64';
  var lgdt = false;
  for (var i = 0; i + 2 < b.length; i++) {
    if (b[i] == 0x0F && b[i + 1] == 0x01 && (b[i + 2] & 0x38) == 0x10 && (b[i + 2] & 0xC0) != 0xC0) {
      lgdt = true;
      break;
    }
  }
  final cr0 = _has(b, const [0x0F, 0x22, 0xC0]);
  if (lgdt && cr0) return 'x86_32';
  return null;
}

/// Çekirdek dosyasının başlığından mimari: ELF, Linux bzImage, Multiboot.
class _KernelInfo {
  String? arch;
  bool linux = false;
  String kind = '';
}

Future<_KernelInfo?> _kernelInfo(_Reader r, int pos, int size) async {
  final head = await r.read(pos, math.min(size, 64 * 1024));
  if (head.length < 64) return null;
  final k = _KernelInfo();
  if (head[0] == 0x7F && head[1] == 0x45 && head[2] == 0x4C && head[3] == 0x46) {
    final cls = head[4];
    final machine = _u16(head, 18);
    if (machine == 62 || cls == 2) {
      k.arch = 'x86_64';
      k.kind = 'ELF64';
    } else if (machine == 3) {
      k.arch = 'x86_32';
      k.kind = 'ELF32';
      // 32-bit ELF içinde uzun moda geçen 64-bit çekirdekler
      final body = await r.read(pos, math.min(size, 2 * 1024 * 1024));
      if (cpuModeOf(body) == 'x86_64') {
        k.arch = 'x86_64';
        k.kind = 'ELF32 → 64-bit';
      }
    } else {
      return null;
    }
  } else if (head.length > 0x240 && String.fromCharCodes(head.sublist(0x202, 0x206)) == 'HdrS') {
    k.linux = true;
    k.kind = 'Linux bzImage';
    k.arch = (_u16(head, 0x236) & 1) != 0 ? 'x86_64' : 'x86_32';
  }
  // Multiboot başlıkları (GRUB ile açılan hobi işletim sistemleri)
  final mb2 = _has(head, const [0xD6, 0x50, 0x52, 0xE8], 32768);
  final mb1 = _has(head, const [0x02, 0xB0, 0xAD, 0x1B], 8192);
  if (mb2 || mb1) {
    k.kind = '${k.kind.isEmpty ? '' : '${k.kind}, '}Multiboot${mb2 ? '2' : ''}';
    if (k.arch == null) {
      final body = await r.read(pos, math.min(size, 2 * 1024 * 1024));
      k.arch = cpuModeOf(body) ?? 'x86_32';
    }
  }
  if (k.arch == null && !k.linux) return null;
  return k;
}

// ===================================================================== ISO

class _IsoFile {
  _IsoFile(this.path, this.lba, this.size, this.dir);
  final String path; // küçük harf, "boot/grub/grub.cfg"
  final int lba;
  final int size;
  final bool dir;
}

Future<List<_IsoFile>> _walkIso(_Reader r) async {
  final pvd = await r.read(32768, 2048);
  final out = <_IsoFile>[];
  final queue = <(String, int, int, int)>[('', _u32(pvd, 158), _u32(pvd, 166), 0)];
  final seen = <int>{};
  while (queue.isNotEmpty && out.length < 3000) {
    final (prefix, lba, size, depth) = queue.removeAt(0);
    if (!seen.add(lba)) continue;
    final data = await r.read(lba * 2048, math.min(size, 256 * 1024));
    var i = 0;
    while (i < data.length) {
      final len = data[i];
      if (len == 0) {
        i = ((i ~/ 2048) + 1) * 2048;
        continue;
      }
      if (len < 34 || i + len > data.length) break;
      final nameLen = data[i + 32];
      if (nameLen > 0 && i + 33 + nameLen <= data.length) {
        final nb = data.sublist(i + 33, i + 33 + nameLen);
        if (!(nameLen == 1 && (nb[0] == 0 || nb[0] == 1))) {
          var name = String.fromCharCodes(nb).split(';').first.toLowerCase();
          if (name.endsWith('.')) name = name.substring(0, name.length - 1);
          final isDir = (data[i + 25] & 2) != 0;
          final f = _IsoFile(prefix + name, _u32(data, i + 2), _u32(data, i + 10), isDir);
          out.add(f);
          if (isDir && depth < 5) queue.add(('${f.path}/', f.lba, f.size, depth + 1));
        }
      }
      i += len;
    }
  }
  return out;
}

class _BootEntry {
  _BootEntry(this.platform, this.media, this.lba, this.count);
  final int platform; // 0 = BIOS, 0xEF = UEFI
  final int media; // 0 no-emul, 1..3 disket, 4 hdd
  final int lba;
  final int count;
}

Future<List<_BootEntry>> _elTorito(_Reader r) async {
  final out = <_BootEntry>[];
  final brvd = await r.read(17 * 2048, 2048);
  if (brvd.length < 0x4B || brvd[0] != 0 || String.fromCharCodes(brvd.sublist(1, 6)) != 'CD001') return out;
  if (!String.fromCharCodes(brvd.sublist(7, 30)).startsWith('EL TORITO')) return out;
  final cat = await r.read(_u32(brvd, 0x47) * 2048, 2048);
  if (cat.length < 64 || cat[0] != 1) return out;
  final platform = cat[1];
  if (cat[32] == 0x88) out.add(_BootEntry(platform, cat[33] & 0x0F, _u32(cat, 40), _u16(cat, 38)));
  var i = 64;
  while (i + 32 <= cat.length) {
    final hdr = cat[i];
    if (hdr != 0x90 && hdr != 0x91) break;
    final plat = cat[i + 1];
    final n = _u16(cat, i + 2);
    i += 32;
    for (var k = 0; k < n && i + 32 <= cat.length; k++, i += 32) {
      if (cat[i] == 0x88) out.add(_BootEntry(plat, cat[i + 1] & 0x0F, _u32(cat, i + 8), _u16(cat, i + 6)));
    }
    if (hdr == 0x91) break;
  }
  return out;
}

Future<MediaReport> inspectIso(RandomAccessFile f, int length) async {
  final r = _Reader(f, length);
  final rep = MediaReport()..boot = 'cd';
  final boots = await _elTorito(r);
  final bios = boots.where((b) => b.platform == 0).toList();
  final efi = boots.any((b) => b.platform == 0xEF);
  if (boots.isEmpty) rep.findings.add(t('Önyükleme kaydı yok (açılabilir CD değil)', 'No boot record (not a bootable CD)'));
  if (bios.isNotEmpty && efi) rep.findings.add('BIOS + UEFI');
  if (bios.isEmpty && efi) {
    rep.uefiOnly = true;
    rep.findings.add(t('Yalnızca UEFI ile açılıyor', 'Boots with UEFI only'));
  }

  final files = await _walkIso(r);
  final byPath = {for (final x in files) x.path: x};
  final names = files.map((x) => x.path.split('/').last).toSet();

  // ---------------------------------------------- önyükleyici ayar dosyaları
  final kernelPaths = <String>[];
  var multiboot = '';
  for (final cfg in files.where((x) =>
      !x.dir &&
      x.size < 65536 &&
      RegExp(r'(grub\.cfg|limine\.cfg|limine\.conf|syslinux\.cfg|isolinux\.cfg|extlinux\.conf)$').hasMatch(x.path))) {
    final txt = String.fromCharCodes(await r.read(cfg.lba * 2048, cfg.size));
    final low = txt.toLowerCase();
    final name = cfg.path.split('/').last;
    if (RegExp(r'protocol\s*[:=]\s*limine').hasMatch(low)) {
      rep.arch = 'x86_64';
      rep.customOs = true;
      rep.findings.add('Limine ($name) → 64-bit');
    }
    for (final m in RegExp(r'^\s*(multiboot2|multiboot|linuxefi|linux16|linux|kernel_path|kernel|path)\s*[:=]?\s*(\S+)',
            multiLine: true)
        .allMatches(low)) {
      final cmd = m.group(1)!;
      var p = m.group(2)!;
      if (cmd.startsWith('multiboot')) multiboot = cmd;
      p = p.replaceFirst(RegExp(r'^(boot\(\):?|boot://|\(\$?root\)|\(cd\))?/*'), '');
      if (p.isNotEmpty) kernelPaths.add(p);
    }
  }
  if (multiboot.isNotEmpty) {
    rep.customOs = true;
    rep.findings.add('GRUB $multiboot');
  }

  // ---------------------------------------------- çekirdek dosyaları
  final candidates = <_IsoFile>[];
  for (final p in kernelPaths) {
    final f = byPath[p];
    if (f != null && !f.dir) candidates.add(f);
  }
  candidates.addAll(files.where((x) =>
      !x.dir &&
      x.size > 1024 &&
      x.size < 128 * 1024 * 1024 &&
      RegExp(r'(vmlinuz|bzimage|kernel|\.elf$|\.krn$|\.kern$|\.bin$|\.sys$|\.exe$|^[^/]*os[^/]*$)')
          .hasMatch(x.path.split('/').last) &&
      !RegExp(r'(isolinux\.bin|eltorito|boot\.cat|ldlinux|\.efi$|grub|limine-bios|memtest)').hasMatch(x.path)));
  final checked = <String>{};
  for (final c in candidates.take(12)) {
    if (!checked.add(c.path)) continue;
    final k = await _kernelInfo(r, c.lba * 2048, c.size);
    if (k == null) continue;
    rep.findings.add('${c.path}: ${k.kind} (${_archText(k.arch)})');
    if (k.linux && multiboot.isEmpty) rep.linuxKernel = true;
    if (!k.linux) rep.customOs = true;
    if (k.arch != null && (rep.arch.isEmpty || _rank(k.arch!) > _rank(rep.arch))) rep.arch = k.arch!;
    if (k.linux || rep.arch == 'x86_64') break;
  }

  // ---------------------------------------------- UEFI uygulamaları
  if (names.contains('bootx64.efi')) {
    rep.findings.add('BOOTX64.EFI');
    if (rep.uefiOnly && rep.arch.isEmpty) rep.arch = 'x86_64';
  } else if (names.contains('bootia32.efi') && rep.uefiOnly && rep.arch.isEmpty) {
    rep.arch = 'x86_32';
  }

  // ---------------------------------------------- önyükleme kodunun kendisi
  if (rep.arch.isEmpty && bios.isNotEmpty) {
    final b = bios.first;
    rep.customOs = true;
    if (b.media >= 1 && b.media <= 3) {
      // Disket öykünmesi: imajın tamamını tara
      final size = const [0, 1228800, 1474560, 2949120][b.media];
      final img = await r.read(b.lba * 2048, size);
      rep.arch = cpuModeOf(img) ?? 'x86_16';
      rep.findings.add('${t('Disket öykünmeli önyükleme', 'Floppy-emulated boot')} → ${_archText(rep.arch)}');
    } else {
      final img = await r.read(b.lba * 2048, math.max(2048, math.min(b.count * 512, 512 * 1024)));
      final mode = cpuModeOf(img);
      if (mode != null) {
        rep.arch = mode;
        rep.findings.add('${t('Önyükleme kodu', 'Boot code')} → ${_archText(mode)}');
      }
    }
  }
  return rep;
}

// ===================================================================== ham imaj

Future<MediaReport> inspectRaw(RandomAccessFile f, int length) async {
  final r = _Reader(f, length);
  final rep = MediaReport()..boot = length <= 2949120 ? 'floppy' : 'disk';
  final s0 = await r.read(0, 512);
  if (s0.length < 512 || s0[510] != 0x55 || s0[511] != 0xAA) {
    rep.findings.add(t('Önyükleme imzası yok (0x55AA)', 'No boot signature (0x55AA)'));
    return rep;
  }
  final isFat = (s0[0] == 0xEB || s0[0] == 0xE9) &&
      _u16(s0, 11) == 512 &&
      (String.fromCharCodes(s0.sublist(54, 57)) == 'FAT' || String.fromCharCodes(s0.sublist(82, 85)) == 'FAT');

  // MBR bölüm tablosu
  if (!isFat) {
    var valid = true, any = false;
    final types = <int>[];
    for (var e = 0; e < 4; e++) {
      final o = 446 + e * 16;
      final status = s0[o];
      final type = s0[o + 4];
      if (status != 0 && status != 0x80) valid = false;
      if (type != 0) {
        any = true;
        types.add(type);
        if (_u32(s0, o + 8) == 0) valid = false;
      }
    }
    if (valid && any) {
      rep.boot = 'disk';
      if (types.contains(0xEE)) {
        rep.arch = 'x86_64';
        rep.findings.add(t('GPT disk (modern, büyük olasılıkla UEFI)', 'GPT disk (modern, likely UEFI)'));
        return rep;
      }
      if (types.contains(0x83) || types.contains(0x82)) {
        rep.linuxPartition = true;
        rep.findings.add(t('Linux bölümü', 'Linux partition'));
      }
      if (types.contains(0x07)) {
        rep.windowsHint = 'ntfs';
        rep.findings.add(t('NTFS bölümü (Windows)', 'NTFS partition (Windows)'));
      }
      if (types.any((x) => x == 0x0B || x == 0x0C || x == 0x06 || x == 0x0E || x == 0x04 || x == 0x01)) {
        rep.findings.add(t('FAT bölümü', 'FAT partition'));
      }
      if (types.contains(0xA5)) rep.bsdHint = 'freebsd';
      if (types.contains(0xA6)) rep.bsdHint = 'openbsd';
      if (types.contains(0xA9)) rep.bsdHint = 'netbsd';
      if (rep.linuxPartition || rep.windowsHint != null || rep.bsdHint != null) return rep;
    }
  }

  // Bölüm tablosu yok / FAT disket: büyük olasılıkla kendi önyükleyicisi olan bir sistem
  rep.customOs = true;
  final body = await r.read(0, math.min(length, 4 * 1024 * 1024));
  rep.arch = cpuModeOf(body) ?? 'x86_16';
  rep.findings.add(
      '${isFat ? t('FAT önyükleme kesimi', 'FAT boot sector') : t('Ham önyükleme kesimi', 'Raw boot sector')} → ${_archText(rep.arch)}');
  return rep;
}

int _rank(String arch) => switch (arch) { 'x86_64' => 3, 'x86_32' => 2, 'x86_16' => 1, _ => 0 };

String _archText(String? arch) => switch (arch) {
      'x86_64' => '64-bit',
      'x86_32' => '32-bit',
      'x86_16' => '16-bit',
      _ => '?',
    };
