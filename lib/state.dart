import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'backend.dart';
import 'i18n.dart';
import 'models.dart';

export 'i18n.dart';

/// Uygulamanın tek durum nesnesi.
class AppState extends ChangeNotifier {
  bool ready = false;
  double setupProgress = 0;
  String? setupError;

  Map<String, dynamic> device = {};
  Map<String, dynamic> settings = {
    'language': 'en',
    'theme': 'dark',
    'filter': 'smooth',
    'mouseMode': 'touch',
    'tbSize': 256,
    'keyboard': 'en-us',
    'mttcg': true,
  };
  List<VmConfig> vms = [];
  String? runningId;

  /// Ekran açık mı (açıksa hata mesajını ekran gösterir).
  bool displayOpen = false;

  String? importName;
  double importProgress = 0;

  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _events.stream;
  StreamSubscription? _sub;

  /// Seçili dil. İlk açılışta İngilizce; eski sürümlerdeki "system" ayarı cihaz diline çevrilir.
  String get lang {
    final l = settings['language'] as String? ?? 'en';
    if (languages.containsKey(l)) return l;
    final device = ui.PlatformDispatcher.instance.locale.languageCode;
    return languages.containsKey(device) ? device : 'en';
  }

  bool get qemuOk => device['qemu64'] == true || device['qemu32'] == true;

  int get totalRamMb => (device['totalRamMb'] as num?)?.toInt() ?? 4096;
  int get cores => (device['cores'] as num?)?.toInt() ?? 4;

  VmConfig? get runningVm {
    for (final v in vms) {
      if (v.id == runningId) return v;
    }
    return null;
  }

  Future<void> init() async {
    _sub ??= Backend.events().listen(_onEvent);
    setupError = null;
    notifyListeners();
    try {
      final s = await Backend.callMap('getSettings');
      settings = {...settings, ...s};
      notifyListeners();
      device = await Backend.callMap('prepare');
      await refresh();
      final st = await Backend.callMap('vmState');
      runningId = st['running'] == true ? st['vmId'] as String? : null;
      ready = true;
    } catch (e) {
      setupError = '$e';
      // runtime eksik olsa bile arayüzü aç (uyarı gösterilir)
      try {
        device = await Backend.callMap('deviceInfo');
        await refresh();
        ready = true;
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Testlerde Java tarafından gelmiş gibi olay üretmek için.
  @visibleForTesting
  void debugEmit(Map<String, dynamic> e) => _onEvent(e);

  void _onEvent(Map<String, dynamic> e) {
    switch (e['type']) {
      case 'setup':
        setupProgress = (e['progress'] as num).toDouble();
        break;
      case 'vm':
        runningId = e['running'] == true ? e['vmId'] as String? : null;
        refresh();
        break;
      case 'import':
        if (e['state'] == 'done') {
          importName = null;
        } else {
          importName = e['name'] as String?;
          importProgress = (e['progress'] as num?)?.toDouble() ?? 0;
        }
        break;
    }
    _events.add(e);
    notifyListeners();
  }

  Future<void> refresh() async {
    final list = await Backend.callList('listVms');
    vms = list.map(VmConfig.fromMap).toList()
      ..sort((a, b) {
        final la = a.lastRunAt == 0 ? a.createdAt : a.lastRunAt;
        final lb = b.lastRunAt == 0 ? b.createdAt : b.lastRunAt;
        return lb.compareTo(la);
      });
    notifyListeners();
  }

  Future<VmConfig> save(VmConfig v) async {
    final saved = VmConfig.fromMap(await Backend.callMap('saveVm', v.toMap()));
    await refresh();
    return saved;
  }

  Future<void> delete(String id, {bool deleteFiles = false}) async {
    await Backend.call('deleteVm', {'id': id, 'deleteFiles': deleteFiles});
    await refresh();
  }

  Future<void> start(String id) async {
    runningId = id;
    notifyListeners();
    try {
      await Backend.call('startVm', {'id': id});
    } catch (_) {
      runningId = null;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> stop({bool force = false}) => Backend.call('stopVm', {'force': force});

  Future<void> setSetting(String key, Object value) async {
    settings[key] = value;
    notifyListeners();
    await Backend.call('saveSettings', settings);
  }

  Future<String?> pickFile({String? sharedFor}) =>
      Backend.call<String>('pickFile', sharedFor == null ? null : {'sharedFor': sharedFor});
}

final app = AppState();
