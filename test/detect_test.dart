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

  test('ada göre mimari algılama (ARM, RISC-V, POWER, Mac)', () {
    expect(detectOs('debian-12.8.0-arm64-netinst')?.id, 'debian_arm64');
    expect(detectOs('debian-12.8.0-armhf-netinst')?.id, 'debian_armhf');
    expect(detectOs('alpine-virt-3.20.3-aarch64')?.id, 'alpine_arm64');
    expect(detectOs('ubuntu-24.04.1-live-server-riscv64')?.id, 'ubuntu_riscv64');
    expect(detectOs('debian-12.8.0-ppc64el-netinst')?.id, 'debian_ppc64');
    expect(detectOs('Mac OS 9.2.2 Install')?.id, 'macos9');
    expect(detectOs('Mac OS X 10.4 Tiger Install DVD')?.id, 'macosx104');
    expect(detectOs('Fedora-Server-dvd-aarch64-41')?.id, 'fedora_arm64');
    expect(detectOs('mystery-os-riscv64')?.id, 'other_riscv64');
    // x86 adları etkilenmemeli
    expect(detectOs('archlinux-2024.11.01-x86_64')?.id, 'arch');
    expect(detectOs('Win10_22H2_English_x64')?.id, 'win10');
    expect(detectOs('debian-12.7.0-amd64-netinst')?.id, 'debian');
  });

  test('ARM64 Linux Image + BOOTAA64.EFI (anlamsız ad ve etiket)', () async {
    final d = await det('mystery-arm.iso');
    expect(d, isNotNull);
    expect(d!.os.arch, 'arm64');
    expect(d.os.family, 'linux');
  }, skip: !exists('mystery-arm.iso'));

  test('gerçek Alpine ARM64 ISO (anlamsız ad)', () async {
    final d = await det('mystery-c.iso');
    expect(d?.os.id, 'alpine_arm64');
  }, skip: !exists('mystery-c.iso'));

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

  test('live-build ile yapılmış Debian tabanlı özel dağıtım (TyrOS benzeri)', () async {
    final d = await det('TyrOS_v1_0 (3).iso');
    expect(d, isNotNull);
    expect(d!.os.id, 'debian');
    expect(d.custom, isFalse);
    expect(d.productName, 'TyrOS 1.0');
    expect(d.suggestedName, 'TyrOS 1.0');
    expect(d.ramHint, 2048);
    final v = VmConfig();
    d.applyTo(v);
    expect(v.ramMb, greaterThanOrEqualTo(2048));
  }, skip: !exists('TyrOS_v1_0 (3).iso'));

  test('live klasörlü, .disk bilgisi olmayan Debian tabanlı ISO', () async {
    final d = await det('livebuild-nodisk.iso');
    expect(d?.os.id, 'debian');
  }, skip: !exists('livebuild-nodisk.iso'));

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
