// İşletim sistemi algılama testleri. Gerçek imajlar CI'da scripts/make_test_media.sh ile üretilir.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strata_vm/models.dart';

void main() {
  final dir = Platform.environment['STRATA_TEST_MEDIA'];

  Future<OsDetection?> det(String name) async {
    final d = await detectOsFromFile('$dir/$name');
    // ignore: avoid_print
    print('$name -> ${d?.os.id} custom=${d?.custom} uefi=${d?.uefi} boot=${d?.boot} '
        'source=${d?.source} findings=${d?.findings}');
    return d;
  }

  bool exists(String name) => dir != null && File('$dir/$name').existsSync();

  test('ada göre algılama', () {
    expect(detectOs('Win10_22H2_Turkish_x64')?.id, 'win10');
    expect(detectOs('Win10_22H2_English_x32')?.id, 'win10_32');
    expect(detectOs('Windows XP Professional SP3')?.id, 'winxp');
    expect(detectOs('Pardus-23.1-XFCE-amd64')?.family, 'linux');
    expect(detectOs('debian-12.7.0-i386-netinst')?.id, 'debian32');
    expect(detectOs('benim isletim sistemim'), isNull);
  });

  test('kendi OS: GRUB + Multiboot2, 32-bit', () async {
    final d = await det('myos32.iso');
    expect(d, isNotNull);
    expect(d!.custom, isTrue);
    expect(d.os.arch, 'x86_32');
    final v = VmConfig();
    d.applyTo(v);
    expect(v.tablet, isFalse);
    expect(v.boot, 'cd');
  }, skip: !exists('myos32.iso'));

  test('kendi OS: GRUB + Multiboot2, uzun moda geçen 64-bit', () async {
    final d = await det('myos64.iso');
    expect(d, isNotNull);
    expect(d!.custom, isTrue);
    expect(d.os.arch, 'x86_64');
  }, skip: !exists('myos64.iso'));

  test('ham 16-bit önyükleme disketi', () async {
    final d = await det('boot16.img');
    expect(d, isNotNull);
    expect(d!.os.arch, 'x86_16');
    expect(d.boot, 'floppy');
  }, skip: !exists('boot16.img'));

  test('korumalı moda geçen 32-bit önyükleme disketi', () async {
    final d = await det('boot32.img');
    expect(d, isNotNull);
    expect(d!.os.arch, 'x86_32');
    expect(d.boot, 'floppy');
  }, skip: !exists('boot32.img'));

  test('gerçek Alpine ISO (anlamsız ad)', () async {
    final d = await det('mystery-a.iso');
    expect(d?.os.id, 'alpine');
  }, skip: !exists('mystery-a.iso'));

  test('gerçek Tiny Core ISO (anlamsız ad)', () async {
    final d = await det('mystery-b.iso');
    expect(d?.os.family, 'linux');
    expect(d?.custom, isFalse);
  }, skip: !exists('mystery-b.iso'));
}
