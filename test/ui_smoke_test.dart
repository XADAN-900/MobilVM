// Arayüz duman testi: her ekranı 8 dilde, dar telefon genişliğinde ve büyük yazı boyutunda çizer.
// Bir yazı/satır taşarsa ("RenderFlex overflowed") test başarısız olur.
// Gerçekçi ölçüm için CI'da Roboto ve Noto Sans Arabic yüklenir (STRATA_TEST_FONTS).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strata_vm/app.dart';
import 'package:strata_vm/models.dart';
import 'package:strata_vm/screens/details_screen.dart';
import 'package:strata_vm/screens/display_screen.dart';
import 'package:strata_vm/screens/editor_screen.dart';
import 'package:strata_vm/screens/home_screen.dart';
import 'package:strata_vm/screens/images_screen.dart';
import 'package:strata_vm/screens/settings_screen.dart';
import 'package:strata_vm/screens/wizard_screen.dart';
import 'package:strata_vm/state.dart';

final _vms = [
  VmConfig(
      id: 'a', name: 'Windows XP Professional Service Pack 3 (Türkçe)', template: 'winxp', arch: 'x86_32',
      ramMb: 512, cpus: 1, isoPath: '/img/WinXP_Professional_SP3_Turkish_with_a_very_long_name.iso',
      diskPath: '/img/Windows_XP.qcow2', createdAt: 1, savedState: true),
  VmConfig(
      id: 'b', name: 'TyrOS 1.0', template: 'debian', arch: 'x86_64', ramMb: 2048, cpus: 2,
      isoPath: '/img/TyrOS_v1_0.iso', diskPath: '/img/TyrOS.qcow2', net: true, portForwards: 'tcp:2222:22, tcp:8080:80',
      sharedFolder: true, diskBus: 'virtio', createdAt: 2),
  VmConfig(id: 'c', name: 'MS-DOS 6.22', template: 'msdos', arch: 'x86_16', ramMb: 16, cpus: 1,
      floppyPath: '/img/Disk1.img', boot: 'floppy', createdAt: 3),
  VmConfig(id: 'd', name: 'Debian ARM64 sunucu', template: 'debian_arm64', arch: 'arm64', ramMb: 1024, cpus: 2,
      isoPath: '/img/debian-arm64.iso', diskPath: '/img/arm.qcow2', createdAt: 4),
  VmConfig(id: 'e', name: 'Mac OS 9.2', template: 'macos9', arch: 'ppc', ramMb: 512, cpus: 1,
      isoPath: '/img/MacOS9.toast', diskPath: '/img/mac.qcow2', createdAt: 5),
  VmConfig(id: 'f', name: 'Debian 68k (Quadra 800)', template: 'debian_m68k', arch: 'm68k', machine: 'q800',
      ramMb: 256, cpus: 1, isoPath: '/img/debian-12.0.0-m68k-NETINST-1.iso', diskPath: '/img/m68k.qcow2',
      kernelPath: '/img/debian-12.0.0-m68k-NETINST-1-kernel', initrdPath: '/img/debian-12.0.0-m68k-NETINST-1-initrd.gz',
      kernelArgs: 'console=tty0', sharedFolder: true, sharedWritable: true, clipboard: false, createdAt: 6),
  VmConfig(id: 'g', name: 'Mac OS 7.6', template: 'macos7', arch: 'm68k', machine: 'q800', ramMb: 128, cpus: 1,
      isoPath: '/img/MacOS76.iso', createdAt: 7),
];

final _images = [
  {'name': 'WinXP_Professional_SP3_Turkish_with_a_very_long_name.iso', 'path': '/img/WinXP.iso', 'size': 734003200, 'modified': 1700000000000},
  {'name': 'TyrOS_v1_0.iso', 'path': '/img/TyrOS_v1_0.iso', 'size': 2147483648, 'modified': 1700000000000},
  {'name': 'Windows_XP.qcow2', 'path': '/img/Windows_XP.qcow2', 'size': 4294967296, 'modified': 1700000000000},
  {'name': 'Disk1.img', 'path': '/img/Disk1.img', 'size': 1474560, 'modified': 1700000000000},
];

Future<void> _loadFonts() async {
  final dir = Platform.environment['STRATA_TEST_FONTS'];
  if (dir == null || !Directory(dir).existsSync()) return;
  final roboto = FontLoader('Roboto');
  for (final f in Directory(dir).listSync().whereType<File>()) {
    if (f.path.endsWith('.ttf') || f.path.endsWith('.otf')) {
      roboto.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
  }
  await roboto.load();
}

void _mockBackend() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(SystemChannels.platform, (c) async => null);
  m.setMockMethodCallHandler(const MethodChannel('strata/backend'), (call) async {
    switch (call.method) {
      case 'listVms':
        return [for (final v in _vms) v.toMap()];
      case 'listImages':
      case 'sharedList':
        return _images;
      case 'snapshotList':
        return [
          {'id': '1', 'name': 'before-update-installation-2026', 'date': 1700000000000, 'vmStateSize': 1000, 'auto': false},
          {'id': '2', 'name': 'clean', 'date': 1700000000000, 'vmStateSize': 0, 'auto': false},
        ];
      case 'vmState':
        return {'running': false};
      case 'vmStats':
        return {'cpu': 187, 'rssMb': 1534, 'uptime': 754, 'status': 'running', 'running': true};
      case 'qemuVersion':
        return 'QEMU emulator version 9.1.2';
      case 'displayAttach':
        return 1;
      case 'log':
        return 'line\n' * 30;
      default:
        return null;
    }
  });
  m.setMockStreamHandler(const EventChannel('strata/events'), MockStreamHandler.inline(onListen: (args, sink) {}));
}

void _seedState() {
  app
    ..ready = true
    ..device = {
      'totalRamMb': 7270, 'cores': 8, 'freeMb': 32358, 'qemu64': true, 'qemu32': true, 'qemuImg': true,
      'runtime': true, 'model': 'samsung SM-A556E', 'android': '15',
      'archs': allArchs,
    }
    ..vms = [..._vms]
    ..runningId = 'b';
}

Widget _wrap(Widget home, String lang, double scale) {
  app.languageOverride = lang;
  return MaterialApp(
    theme: buildTheme(Brightness.dark),
    locale: Locale(lang),
    supportedLocales: [for (final l in languages.keys) Locale(l)],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: home,
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });
  setUp(() {
    _mockBackend();
    _seedState();
  });
  tearDown(() => app.languageOverride = null);

  // Dar telefon (320) ve normal telefon (360); yüksekliği büyük tut ki listedeki her şey çizilsin.
  const widths = [320.0, 360.0];
  const scales = [1.0, 1.3];

  for (final lang in languages.keys) {
    for (final width in widths) {
      for (final scale in scales) {
        final tag = '[$lang ${width.toInt()}px x$scale]';

        Future<void> setSize(WidgetTester tester, {double height = 2600}) async {
          tester.view.physicalSize = Size(width * 3, height * 3);
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
        }

        Future<void> done(WidgetTester tester) async {
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 3));
        }

        testWidgets('ana ekran + VM menüsü $tag', (tester) async {
          await setSize(tester);
          await tester.pumpWidget(_wrap(const HomeScreen(), lang, scale));
          await tester.pump(const Duration(milliseconds: 500));
          await tester.longPress(find.text('MS-DOS 6.22').first);
          await tester.pump(const Duration(milliseconds: 600));
          await done(tester);
        });

        testWidgets('ayarlar $tag', (tester) async {
          await setSize(tester);
          await tester.pumpWidget(_wrap(const SettingsScreen(), lang, scale));
          await tester.pump(const Duration(milliseconds: 500));
          await done(tester);
        });

        testWidgets('imaj kütüphanesi $tag', (tester) async {
          await setSize(tester);
          await tester.pumpWidget(_wrap(const ImagesScreen(), lang, scale));
          await tester.pump(const Duration(milliseconds: 500));
          await done(tester);
        });

        for (final vmIndex in [1, 3, 4, 5, 6]) {
          testWidgets('VM ayarları ${_vms[vmIndex].archLabel} #$vmIndex $tag', (tester) async {
            await setSize(tester, height: 7000);
            await tester.pumpWidget(_wrap(EditorScreen(vm: _vms[vmIndex]), lang, scale));
            await tester.pump(const Duration(milliseconds: 500));
            // "Gelişmiş" en alttaki; "Gelişmiş açılış" 68k'da zaten açık, diğerlerinde açılır
            await tester.tap(find.byType(ExpansionTile).last);
            await tester.pump(const Duration(milliseconds: 600));
            if (_vms[vmIndex].arch != 'm68k') {
              await tester.tap(find.byType(ExpansionTile).first);
              await tester.pump(const Duration(milliseconds: 600));
            }
            await done(tester);
          });
        }

        testWidgets('ayrıntılar $tag', (tester) async {
          await setSize(tester, height: 4200);
          final id = switch (lang) { 'ar' || 'ru' => 'd', 'de' || 'pt' || 'fr' => 'f', _ => 'b' };
          await tester.pumpWidget(_wrap(DetailsScreen(vmId: id), lang, scale));
          await tester.pump(const Duration(milliseconds: 500));
          await done(tester);
        });

        testWidgets('sihirbaz 4 adım $tag', (tester) async {
          await setSize(tester);
          await tester.pumpWidget(_wrap(const WizardScreen(), lang, scale));
          await tester.pump(const Duration(milliseconds: 500));
          await tester.enterText(find.byType(TextField).first, 'Windows XP');
          await tester.pump(const Duration(milliseconds: 300));
          for (var step = 0; step < 3; step++) {
            await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
            await tester.pump(const Duration(milliseconds: 400));
          }
          await done(tester);
        });

        testWidgets('VM ekranı, araç çubuğu, tuşlar, menü $tag', (tester) async {
          await setSize(tester, height: width * 2);
          await tester.pumpWidget(_wrap(DisplayScreen(vm: _vms[1]), lang, scale));
          await tester.pump(const Duration(milliseconds: 300));
          app.debugEmit({'type': 'display', 'state': 'connected', 'width': 1024, 'height': 768});
          await tester.pump(const Duration(milliseconds: 300));
          app.debugEmit({'type': 'clipboard', 'text': 'merhaba dünya'});
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.byIcon(Icons.space_bar_rounded));
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.byIcon(Icons.more_vert_rounded));
          await tester.pump(const Duration(milliseconds: 600));
          await done(tester);
        });
      }
    }
  }
}
