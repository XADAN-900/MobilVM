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

  test('yeni sistemler ve 68k adla algılanır', () {
    final cases = {
      'en_windows_server_2019_x64_dvd': 'win2019',
      'Windows Server 2003 R2 Enterprise': 'win2003',
      'SW_DVD9_Win_Server_STD_CORE_2022': 'win2022',
      'Windows NT 4.0 Workstation': 'winnt4',
      'Windows XP Professional x64 Edition': 'winxp64',
      'Windows XP Professional SP3': 'winxp',
      'Windows 2.03': 'win2',
      'Windows 1.01': 'win1',
      'Windows 3.11': 'win31',
      'DR-DOS 7.03': 'drdos',
      'PC-DOS 2000': 'pcdos',
      'OS2 Warp 4': 'os2',
      'ArcaOS-5.1.0': 'arcaos',
      'BeOS R5 Personal': 'beos',
      'haiku-r1beta5-x86_64-anyboot': 'haiku',
      'sol-11_4-text-x86': 'solaris',
      'OI-hipster-text-20240426': 'openindiana',
      'minix_R3.3.0-588a35b': 'minix',
      '9front-10522.amd64': 'plan9',
      'TempleOS': 'templeos',
      'serenity-x86_64': 'serenity',
      'redox_demo_x86_64_2024-05-01_1048_livedisk': 'redox',
      'android-x86_64-9.0-r2': 'android_x86',
      'Bliss-v16.9.7-x86_64-OFFICIAL-gapps': 'android_x86',
      'chromeos_15917.71.0_reven_recovery': 'chromeos',
      'Pardus-23.1-XFCE-amd64': 'pardus',
      'kali-linux-2024.3-installer-amd64': 'kali',
      'manjaro-kde-24.1.1-241011-linux610': 'manjaro',
      'openSUSE-Leap-15.6-DVD-x86_64': 'opensuse',
      'Rocky-9.4-x86_64-minimal': 'rhel',
      'slackware64-15.0-install-dvd': 'slackware',
      'fossapup64-9.5': 'puppy',
      'dsl-2024.rc7': 'dsl',
      'FreeBSD-14.1-RELEASE-i386-disc1': 'freebsd32',
      'FreeBSD-14.1-RELEASE-amd64-disc1': 'freebsd',
      'DragonFly-x86_64-20240520-DEV': 'dragonfly',
      'debian-12.0.0-m68k-NETINST-1': 'debian_m68k',
      'mystery-m68k': 'other_m68k',
      'System 7.5.3': 'macos7',
      'Mac OS 8.1 CD': 'macos8_68k',
      'Mac OS 9.2.2 Install': 'macos9',
      'archlinux-2024.11.01-x86_64': 'arch',
      'debian-12.7.0-amd64-netinst': 'debian',
    };
    for (final e in cases.entries) {
      expect(detectOs(e.key)?.id, e.value, reason: e.key);
    }
    // Her yeni tür varsayılan donanımla oluşturulabilmeli
    for (final os in osCatalog) {
      final v = os.create();
      expect(v.arch, os.arch, reason: os.id);
      expect(v.ramMb, lessThanOrEqualTo(archMaxRam(v.arch)), reason: os.id);
      expect(v.cpus, lessThanOrEqualTo(archMaxCpus(v.arch)), reason: os.id);
      expect(soundOptions(v).containsKey(v.sound), isTrue, reason: os.id);
      if (v.arch == 'm68k') expect(v.machine, 'q800', reason: os.id);
    }
    expect(osCatalog.map((o) => o.id).toSet().length, osCatalog.length);
  });

  test('68k açılış kuralı ve ses seçenekleri', () {
    final mac = osById('macos7').create();
    expect(mac.bootProblem, isNotNull);
    mac.biosPath = '/x/quadra800.rom';
    expect(mac.bootProblem, isNull);
    final virt = osById('linux_m68k').create()..machine = 'virt';
    expect(virt.bootProblem, isNotNull);
    virt.kernelPath = '/x/vmlinux';
    expect(virt.bootProblem, isNull);
    expect(soundOptions(osById('freedos').create()).containsKey('sb16'), isTrue);
    expect(soundOptions(osById('debian_arm64').create()).containsKey('sb16'), isFalse);
    expect(clipboardCapable(osById('win98').create()), isFalse);
    expect(clipboardCapable(osById('ubuntu').create()), isTrue);
    expect(osById('win98').create().clipboard, isFalse);
    final w = osById('debian').create()
      ..diskPath = '/x/d.qcow2'
      ..sharedFolder = true
      ..sharedWritable = true;
    expect(w.saveStateCapable, isFalse);
    expect(osById('debian').create().diskBus, 'virtio');
    expect(osById('win10').create().diskBus, 'ide');
    expect(osById('debian32').create().diskBus, 'ide');
    expect(w.snapshotCapable, isFalse);
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
