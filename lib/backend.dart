import 'package:flutter/services.dart';

/// Java arka planına (StrataBridge.java) erişim.
class Backend {
  static const _methods = MethodChannel('strata/backend');
  static const _events = EventChannel('strata/events');

  static Stream<Map<String, dynamic>> events() =>
      _events.receiveBroadcastStream().map((e) => Map<String, dynamic>.from(e as Map));

  static Future<T?> call<T>(String method, [Object? args]) => _methods.invokeMethod<T>(method, args);

  static Future<Map<String, dynamic>> callMap(String method, [Object? args]) async {
    final r = await _methods.invokeMethod<Map>(method, args);
    return r == null ? <String, dynamic>{} : Map<String, dynamic>.from(r);
  }

  static Future<List<Map<String, dynamic>>> callList(String method, [Object? args]) async {
    final r = await _methods.invokeMethod<List>(method, args);
    return r == null ? [] : r.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Sonucu beklenmeyen hızlı çağrılar (fare/klavye olayları).
  static void fire(String method, [Object? args]) {
    _methods.invokeMethod(method, args).catchError((_) => null);
  }
}
