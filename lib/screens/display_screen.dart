import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backend.dart';
import '../keysyms.dart';
import '../models.dart';
import '../state.dart';
import '../widgets/common.dart';
import '../widgets/logo.dart';
import '../widgets/media_picker.dart';

enum MouseMode { touch, trackpad }

/// VM ekranı: Java tarafındaki DisplaySession bir Flutter Texture'ına çizer,
/// dokunma ve klavye olayları VNC olaylarına çevrilip geri gönderilir.
class DisplayScreen extends StatefulWidget {
  const DisplayScreen({super.key, required this.vm});
  final VmConfig vm;

  @override
  State<DisplayScreen> createState() => _DisplayScreenState();
}

class _DisplayScreenState extends State<DisplayScreen> {
  static const _sentinel = '​​​​​​​​';

  int? _tex;
  int _fbW = 0, _fbH = 0;
  bool _connected = false;
  bool _ended = false;
  int _reconnects = 0;
  StreamSubscription? _sub;

  // görünüm
  double _zoom = 1;
  Offset _pan = Offset.zero;
  Size _view = Size.zero;

  // giriş
  late MouseMode _mode;
  Offset _cursor = Offset.zero;
  bool _toolbar = true;
  bool _keyBar = false;
  bool _paused = false;
  bool _landscape = false;
  Timer? _statsTimer;
  Map<String, dynamic> _stats = {};
  bool _savingState = false;
  bool _muted = app.settings['muted'] == true;
  String _lastGuestClip = '';
  final Set<int> _sticky = {};
  final Map<PhysicalKeyboardKey, int> _pressed = {};
  late final FocusNode _hwFocus = FocusNode(onKeyEvent: _onKey);
  late final FocusNode _txtFocus = FocusNode(onKeyEvent: _onKey);
  final _txt = TextEditingController(text: _sentinel);

  // jest durumu
  final Map<int, Offset> _ptrs = {};
  Offset _downPos = Offset.zero;
  DateTime _downAt = DateTime.now();
  bool _moved = false, _dragging = false, _longFired = false, _dragLock = false;
  bool _multi = false, _scrolled = false, _zooming = false;
  Timer? _longTimer;
  double _startDist = 1, _startZoom = 1, _lastScrollY = 0;
  Offset _startCentroid = Offset.zero, _startPan = Offset.zero;
  DateTime _multiAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    // PS/2 fare (USB tablet kapalı) göreli çalışır: touchpad modu daha doğal
    _mode = app.settings['mouseMode'] == 'trackpad' ||
            (isX86Arch(widget.vm.arch) && (!widget.vm.tablet || widget.vm.machine == 'isapc')) ||
            (widget.vm.arch == 'm68k' && widget.vm.machine != 'virt')
        ? MouseMode.trackpad
        : MouseMode.touch;
    app.displayOpen = true;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    Backend.fire('keepScreenOn', {'on': true});
    _sub = app.events.listen(_onEvent);
    _attach();
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollStats());
    _pollStats();
  }

  Future<void> _pollStats() async {
    try {
      final st = await Backend.callMap('vmStats');
      if (mounted) setState(() => _stats = st);
    } catch (_) {}
  }

  String get _statsText {
    final cpu = _stats['cpu'];
    final rss = _stats['rssMb'];
    final up = (_stats['uptime'] as num?)?.toInt() ?? 0;
    final status = _stats['status'] as String?;
    final parts = <String>[
      if (cpu != null) 'CPU $cpu%',
      if (rss != null) 'RAM ${fmtMb((rss as num).toInt())}',
      '${up ~/ 60}:${(up % 60).toString().padLeft(2, '0')}',
      if (status == 'paused') t('duraklatıldı', 'paused'),
    ];
    return parts.join('  ·  ');
  }

  @override
  void dispose() {
    _sub?.cancel();
    _longTimer?.cancel();
    _statsTimer?.cancel();
    _releaseSticky();
    Backend.fire('displayDetach');
    Backend.fire('keepScreenOn', {'on': false});
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([]);
    app.displayOpen = false;
    _hwFocus.dispose();
    _txtFocus.dispose();
    _txt.dispose();
    super.dispose();
  }

  Future<void> _attach() async {
    try {
      final id = await Backend.call<int>('displayAttach');
      if (mounted) setState(() => _tex = id);
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  void _onEvent(Map<String, dynamic> e) {
    if (!mounted) return;
    if (e['type'] == 'display') {
      switch (e['state']) {
        case 'connected':
        case 'resize':
          final w = (e['width'] as num).toInt(), h = (e['height'] as num).toInt();
          setState(() {
            if (!_connected || _fbW == 0) _cursor = Offset(w / 2, h / 2);
            _fbW = w;
            _fbH = h;
            _connected = true;
            _reconnects = 0;
            _clampPan();
          });
          break;
        case 'disconnected':
          setState(() => _connected = false);
          if (!_ended && app.runningId == widget.vm.id && _reconnects < 5) {
            _reconnects++;
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted && !_ended) _attach();
            });
          }
          break;
      }
    } else if (e['type'] == 'clipboard') {
      // Misafir bir metin kopyaladı: telefon panosuna al
      final text = (e['text'] as String?) ?? '';
      if (text.isEmpty || text == _lastGuestClip) return;
      _lastGuestClip = text;
      Clipboard.setData(ClipboardData(text: text));
      toast(context, t('VM\'den panoya kopyalandı', 'Copied from the VM to the clipboard'));
    } else if (e['type'] == 'vm' && e['running'] == false && e['vmId'] == widget.vm.id) {
      _onVmEnded((e['exitCode'] as num?)?.toInt() ?? 0);
    }
  }

  Future<void> _onVmEnded(int code) async {
    if (_ended) return;
    _ended = true;
    if (_savingState) {
      if (mounted) {
        Navigator.of(context).popUntil((r) => r is! PopupRoute);
        toast(context, t('Durum kaydedildi. Başlatınca kaldığın yerden devam eder.',
            'State saved. Starting the VM resumes where you left off.'));
        Navigator.pop(context);
      }
      return;
    }
    final log = await Backend.call<String>('log') ?? '';
    if (!mounted) return;
    final lines = log.trim().split('\n');
    final tail = lines.length > 14 ? lines.sublist(lines.length - 14).join('\n') : lines.join('\n');
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(code == 0 ? t('Sanal makine kapandı', 'Virtual machine stopped') : t('Sanal makine hata verdi', 'Virtual machine failed')),
        content: code == 0
            ? null
            : SingleChildScrollView(
                child: SelectableText(tail, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
              ),
        actions: [
          if (code != 0)
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: log)),
              child: Text(t('Günlüğü kopyala', 'Copy log')),
            ),
          FilledButton(onPressed: () => Navigator.pop(c), child: Text(t('Tamam', 'OK'))),
        ],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  // ================================================================ geometri

  Rect get _baseRect {
    if (_fbW == 0 || _view.isEmpty) return Rect.zero;
    final s = math.min(_view.width / _fbW, _view.height / _fbH);
    final w = _fbW * s, h = _fbH * s;
    return Rect.fromLTWH((_view.width - w) / 2, (_view.height - h) / 2, w, h);
  }

  Rect get _rect {
    final b = _baseRect;
    return Rect.fromCenter(center: b.center + _pan, width: b.width * _zoom, height: b.height * _zoom);
  }

  void _clampPan() {
    final b = _baseRect;
    final mx = math.max(0.0, (b.width * _zoom - _view.width) / 2);
    final my = math.max(0.0, (b.height * _zoom - _view.height) / 2);
    _pan = Offset(_pan.dx.clamp(-mx, mx).toDouble(), _pan.dy.clamp(-my, my).toDouble());
  }

  Offset _toFb(Offset p) {
    final r = _rect;
    if (r.isEmpty || _fbW == 0) return Offset.zero;
    return Offset(
      ((p.dx - r.left) / r.width * _fbW).clamp(0, _fbW - 1).toDouble(),
      ((p.dy - r.top) / r.height * _fbH).clamp(0, _fbH - 1).toDouble(),
    );
  }

  // ================================================================ fare

  void _ptr(Offset fb, int buttons) =>
      Backend.fire('pointer', {'x': fb.dx.round(), 'y': fb.dy.round(), 'buttons': buttons});

  void _click(Offset fb, int button) {
    _ptr(fb, 0);
    _ptr(fb, button);
    _ptr(fb, 0);
  }

  void _wheel(Offset fb, bool down) {
    _ptr(fb, down ? 16 : 8);
    _ptr(fb, 0);
  }

  Offset get _here => _mode == MouseMode.touch ? _toFb(_downPos) : _cursor;

  Offset _centroid() {
    var s = Offset.zero;
    for (final p in _ptrs.values) {
      s += p;
    }
    return s / _ptrs.length.toDouble();
  }

  double _spread() {
    final l = _ptrs.values.toList();
    return l.length < 2 ? 1 : (l[0] - l[1]).distance;
  }

  void _onDown(PointerDownEvent e) {
    if (!_connected) return;
    _ptrs[e.pointer] = e.localPosition;
    if (_ptrs.length == 1) {
      _downPos = e.localPosition;
      _downAt = DateTime.now();
      _moved = _dragging = _longFired = _dragLock = false;
      _multi = false;
      if (_mode == MouseMode.touch) _ptr(_toFb(_downPos), 0);
      _longTimer?.cancel();
      _longTimer = Timer(const Duration(milliseconds: 480), _onLongPress);
    } else if (_ptrs.length == 2) {
      _longTimer?.cancel();
      if (_dragging || _dragLock) _ptr(_here, 0);
      _dragging = _dragLock = false;
      _multi = true;
      _scrolled = _zooming = false;
      _multiAt = DateTime.now();
      _startDist = math.max(1, _spread());
      _startZoom = _zoom;
      _startCentroid = _centroid();
      _startPan = _pan;
      _lastScrollY = _startCentroid.dy;
    }
  }

  void _onLongPress() {
    if (_moved || _multi || _ptrs.length != 1) return;
    _longFired = true;
    HapticFeedback.mediumImpact();
    if (_mode == MouseMode.touch) {
      _click(_toFb(_downPos), 4); // sağ tık
    } else {
      _dragLock = true; // touchpad: basılı tutup sürükle
      _ptr(_cursor, 1);
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (!_ptrs.containsKey(e.pointer)) return;
    _ptrs[e.pointer] = e.localPosition;

    if (_multi) {
      if (_ptrs.length < 2) return;
      final ratio = _spread() / _startDist;
      final c = _centroid();
      if (_zooming || (!_scrolled && (ratio - 1).abs() > 0.15)) {
        _zooming = true;
        setState(() {
          _zoom = (_startZoom * ratio).clamp(1.0, 5.0).toDouble();
          _pan = _startPan + (c - _startCentroid);
          _clampPan();
        });
      } else {
        final dy = c.dy - _lastScrollY;
        if (dy.abs() > 28) {
          _wheel(_here, dy < 0);
          _lastScrollY = c.dy;
          _scrolled = true;
        }
      }
      return;
    }

    if (!_moved && (e.localPosition - _downPos).distance > 9) {
      _moved = true;
      if (!_longFired) _longTimer?.cancel();
    }
    if (!_moved && !_dragLock) return;

    if (_mode == MouseMode.touch) {
      if (_longFired) return;
      if (!_dragging) {
        _dragging = true;
        _ptr(_toFb(_downPos), 1);
      }
      _ptr(_toFb(e.localPosition), 1);
    } else {
      final r = _rect;
      if (r.width <= 0) return;
      final speed = (_fbW / r.width) * 1.5;
      final d = e.delta * speed;
      _cursor = Offset(
        (_cursor.dx + d.dx).clamp(0, math.max(0, _fbW - 1)).toDouble(),
        (_cursor.dy + d.dy).clamp(0, math.max(0, _fbH - 1)).toDouble(),
      );
      _ptr(_cursor, _dragLock ? 1 : 0);
    }
  }

  void _onUp(PointerEvent e) {
    if (!_ptrs.containsKey(e.pointer)) return;
    _ptrs.remove(e.pointer);
    _longTimer?.cancel();

    if (_multi) {
      if (_ptrs.isEmpty) {
        final quick = DateTime.now().difference(_multiAt).inMilliseconds < 320;
        if (!_scrolled && !_zooming && quick && e is PointerUpEvent) _click(_here, 4);
        _multi = false;
      }
      return;
    }
    if (e is! PointerUpEvent) {
      if (_dragging || _dragLock) _ptr(_here, 0);
      return;
    }

    if (_mode == MouseMode.touch) {
      if (_dragging) {
        _ptr(_toFb(e.localPosition), 0);
      } else if (!_moved && !_longFired) {
        _click(_toFb(e.localPosition), 1);
      }
    } else {
      if (_dragLock) {
        _ptr(_cursor, 0);
      } else if (!_moved && !_longFired && DateTime.now().difference(_downAt).inMilliseconds < 300) {
        _click(_cursor, 1);
      }
    }
    _dragging = _dragLock = false;
  }

  // ================================================================ klavye

  void _key(int ks, bool down) => Backend.fire('key', {'keysym': ks, 'down': down});

  void _tap(int ks) {
    _key(ks, true);
    _key(ks, false);
    _releaseSticky();
  }

  void _typeChar(String c) {
    final ks = Ks.forChar(c);
    final shiftHeld = _sticky.contains(Ks.shiftL) || _pressed.values.contains(Ks.shiftL) || _pressed.values.contains(0xffe2);
    final wrap = Ks.needsShift(c) && !shiftHeld;
    if (wrap) _key(Ks.shiftL, true);
    _key(ks, true);
    _key(ks, false);
    if (wrap) _key(Ks.shiftL, false);
    _releaseSticky();
  }

  void _toggleSticky(int ks) {
    setState(() {
      if (_sticky.remove(ks)) {
        _key(ks, false);
      } else {
        _sticky.add(ks);
        _key(ks, true);
      }
    });
  }

  void _releaseSticky() {
    if (_sticky.isEmpty) return;
    for (final ks in _sticky) {
      _key(ks, false);
    }
    _sticky.clear();
    if (mounted) setState(() {});
  }

  void _combo(List<int> mods, int key) {
    for (final m in mods) {
      _key(m, true);
    }
    _key(key, true);
    _key(key, false);
    for (final m in mods.reversed) {
      _key(m, false);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyDownEvent || e is KeyRepeatEvent) {
      var ks = Ks.forLogical(e.logicalKey);
      if (ks == null) {
        final c = e.character;
        if (c != null && c.isNotEmpty && c.runes.length == 1 && c.codeUnitAt(0) >= 0x20) ks = Ks.forChar(c);
      }
      if (ks == null) return KeyEventResult.ignored;
      _pressed[e.physicalKey] = ks;
      _key(ks, true);
      return KeyEventResult.handled;
    }
    if (e is KeyUpEvent) {
      final ks = _pressed.remove(e.physicalKey);
      if (ks == null) return KeyEventResult.ignored;
      _key(ks, false);
      if (!Ks.isModifier(ks)) _releaseSticky();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onText(String value) {
    if (value == _sentinel) return;
    if (value.length < _sentinel.length) {
      for (var i = 0; i < _sentinel.length - value.length; i++) {
        _tap(Ks.backspace);
      }
    } else {
      final added = value.startsWith(_sentinel) ? value.substring(_sentinel.length) : value.replaceAll('​', '');
      for (final r in added.runes) {
        _typeChar(String.fromCharCode(r));
      }
    }
    _txt.value = const TextEditingValue(
      text: _sentinel,
      selection: TextSelection.collapsed(offset: _sentinel.length),
    );
  }

  void _toggleKeyboard(bool visible) {
    if (visible) {
      _txtFocus.unfocus();
      _hwFocus.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    } else {
      _txtFocus.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
    }
  }

  // ================================================================ araç çubuğu

  // Araç çubuğu süreyle kaybolmaz; kullanıcı kendisi açar/kapatır.
  void _showToolbar() => setState(() => _toolbar = true);

  void _hideToolbar() => setState(() => _toolbar = false);

  Future<void> _qmp(String cmd, [Map<String, dynamic>? args]) async {
    try {
      await Backend.call('qmp', {'command': cmd, 'args': args ?? {}});
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  Future<void> _menuAction(String a) async {
    switch (a) {
      case 'cad':
        _combo([Ks.ctrlL, Ks.altL], Ks.del);
        break;
      case 'shot':
        try {
          final p = await Backend.call<String>('screenshot');
          if (mounted) toast(context, '${t('Kaydedildi', 'Saved')}: $p');
        } catch (e) {
          if (mounted) toast(context, '$e');
        }
        break;
      case 'cd':
        final p = await chooseMedia(context, 'cd', vmId: widget.vm.id);
        if (p != null) {
          await Backend.call('changeCd', {'path': p}).catchError((e) {
            if (mounted) toast(context, '$e');
          });
          if (mounted) toast(context, '${t('CD takıldı', 'CD inserted')}: ${baseName(p)}');
        }
        break;
      case 'eject':
        await Backend.call('changeCd', {'path': ''}).catchError((_) => null);
        if (mounted) toast(context, t('CD çıkarıldı', 'CD ejected'));
        break;
      case 'log':
        if (mounted) await showLogSheet(context);
        break;
      case 'paste':
        await _pasteText();
        break;
      case 'clip':
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final text = data?.text ?? '';
        if (text.isEmpty) {
          if (mounted) toast(context, t('Pano boş', 'The clipboard is empty'));
          break;
        }
        _lastGuestClip = text;
        final ok = await Backend.call<bool>('clipboardSend', {'text': text}).catchError((_) => false);
        if (mounted) {
          toast(context, ok == true
              ? t('Pano VM\'e gönderildi (misafirde Ctrl+V)', 'Clipboard sent to the VM (Ctrl+V in the guest)')
              : t('Gönderilemedi', 'Could not send'));
        }
        break;
      case 'rotate':
        setState(() => _landscape = !_landscape);
        await SystemChrome.setPreferredOrientations(_landscape
            ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
            : []);
        break;
      case 'save':
        await _saveState();
        break;
      case 'reset':
        if (mounted &&
            await confirm(context, t('Yeniden başlatılsın mı?', 'Restart?'),
                t('Misafir sistem anında sıfırlanır.', 'The guest is reset immediately.'),
                ok: t('Yeniden başlat', 'Restart'))) {
          await _qmp('system_reset');
        }
        break;
      case 'acpi':
        await _qmp('system_powerdown');
        if (mounted) toast(context, t('Kapatma sinyali gönderildi', 'Shutdown signal sent'));
        break;
      case 'kill':
        if (mounted &&
            await confirm(context, t('Zorla kapatılsın mı?', 'Force stop?'),
                t('Fişi çekmek gibidir; kaydedilmemiş veriler kaybolur.', 'Like pulling the plug; unsaved data is lost.'),
                ok: t('Zorla kapat', 'Force stop'), danger: true)) {
          await app.stop(force: true);
        }
        break;
    }
  }

  /// Telefon panosundaki metni VM'e klavyeyle yazar.
  Future<void> _pasteText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isEmpty) {
      if (mounted) toast(context, t('Pano boş', 'Clipboard is empty'));
      return;
    }
    if (text.length > 4000) {
      if (mounted) toast(context, t('Metin çok uzun (en fazla 4000 karakter)', 'Text too long (max 4000 characters)'));
      return;
    }
    var i = 0;
    for (final r in text.runes) {
      final c = String.fromCharCode(r);
      if (c == '\r') continue;
      if (c == '\n') {
        _tap(Ks.enter);
      } else {
        _typeChar(c);
      }
      if (++i % 16 == 0) await Future.delayed(const Duration(milliseconds: 30));
      if (!mounted || _ended) return;
    }
  }

  /// VirtualBox'taki "Makine durumunu kaydet".
  Future<void> _saveState() async {
    if (!widget.vm.snapshotCapable) {
      toast(context, t('Durum kaydetmek için qcow2 disk gerekir.', 'Saving state requires a qcow2 disk.'));
      return;
    }
    if (!widget.vm.saveStateCapable) {
      toast(context, t('UEFI\'li VM\'lerde "Durumu kaydet" çalışmaz; anlık görüntüler yalnızca VM kapalıyken alınabilir.',
          'With UEFI, "Save state" does not work; snapshots can be taken only while the VM is off.'));
      return;
    }
    final ok = await confirm(
      context,
      t('Durumu kaydet ve kapat', 'Save state and close'),
      t('Bellek dahil her şey diske yazılır ve VM kapanır. Sonra başlattığında tam kaldığın yerden devam eder.',
          'Everything including memory is written to disk and the VM closes. Next start resumes exactly where you left off.'),
      ok: t('Kaydet', 'Save'),
    );
    if (!ok || !mounted) return;
    _savingState = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 20),
          Expanded(child: Text(t('Durum kaydediliyor…', 'Saving state…'))),
        ]),
      ),
    );
    try {
      await Backend.call('saveState', {'id': widget.vm.id});
    } catch (e) {
      _savingState = false;
      if (mounted) {
        Navigator.of(context).pop();
        toast(context, '${t('Kaydedilemedi', 'Could not save')}: $e');
      }
    }
  }

  // ================================================================ arayüz

  @override
  Widget build(BuildContext context) {
    final kbVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    final sharp = app.settings['filter'] == 'sharp';
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: Column(children: [
        Expanded(
          child: LayoutBuilder(builder: (context, cons) {
            _view = cons.biggest;
            final r = _rect;
            return Stack(children: [
              if (_tex != null && _fbW > 0)
                Positioned.fromRect(
                  rect: r,
                  child: Texture(
                    textureId: _tex!,
                    filterQuality: sharp ? FilterQuality.none : FilterQuality.medium,
                  ),
                ),
              Positioned.fill(
                child: Focus(
                  focusNode: _hwFocus,
                  autofocus: true,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _onDown,
                    onPointerMove: _onMove,
                    onPointerUp: _onUp,
                    onPointerCancel: _onUp,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              if (!_connected) _booting(),
              // görünmez metin alanı: yumuşak klavyeden gelen yazıyı yakalar
              Positioned(
                left: 0,
                bottom: 0,
                width: 1,
                height: 1,
                child: Opacity(
                  opacity: 0,
                  child: TextField(
                    controller: _txt,
                    focusNode: _txtFocus,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    keyboardType: TextInputType.visiblePassword,
                    textInputAction: TextInputAction.send,
                    showCursor: false,
                    enableInteractiveSelection: false,
                    onChanged: _onText,
                    onSubmitted: (_) => _tap(Ks.enter),
                    onEditingComplete: () {},
                  ),
                ),
              ),
              _toolbarWidget(kbVisible),
              if (_toolbar && _connected && _stats['cpu'] != null)
                Positioned(
                  left: 10,
                  bottom: 10,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xCC151833),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(_statsText, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                    ),
                  ),
                ),
              if (!_toolbar)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _showToolbar,
                      child: Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xB3151833),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                ),
            ]);
          }),
        ),
        if (_keyBar) _keyBarWidget(),
      ]),
    );
  }

  Widget _booting() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const StrataLogo(size: 72),
            const SizedBox(height: 24),
            Text(widget.vm.name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            const SizedBox(width: 160, child: LinearProgressIndicator()),
            const SizedBox(height: 12),
            Text(t('Sanal makine başlatılıyor…', 'Starting virtual machine…'),
                style: const TextStyle(color: Colors.white60)),
            if (_stats['cpu'] != null) ...[
              const SizedBox(height: 8),
              Text(_statsText, style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _toolbarWidget(bool kbVisible) {
    Widget btn(IconData i, String tip, VoidCallback onTap, {bool active = false}) => IconButton(
          tooltip: tip,
          onPressed: () {
            onTap();
          },
          icon: Icon(i, color: active ? const Color(0xFFA5B4FC) : Colors.white),
        );

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      top: _toolbar ? 8 : -80,
      left: 8,
      right: 8,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: const Color(0xE6151833),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white12),
          ),
          // Menü ve gizle düğmeleri her zaman görünür; ortadaki düğmeler dar ekranda kaydırılır
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              btn(Icons.arrow_back_rounded, t('Geri (VM çalışmaya devam eder)', 'Back (VM keeps running)'),
                  () => Navigator.pop(context)),
              btn(Icons.keyboard_rounded, t('Klavye', 'Keyboard'), () => _toggleKeyboard(kbVisible), active: kbVisible),
              btn(Icons.space_bar_rounded, t('Özel tuşlar', 'Special keys'),
                  () => setState(() => _keyBar = !_keyBar), active: _keyBar),
              btn(
                _mode == MouseMode.touch ? Icons.touch_app_rounded : Icons.mouse_rounded,
                _mode == MouseMode.touch ? t('Mod: dokunmatik', 'Mode: touch') : t('Mod: touchpad', 'Mode: trackpad'),
                () {
                  setState(() => _mode = _mode == MouseMode.touch ? MouseMode.trackpad : MouseMode.touch);
                  toast(context, _mode == MouseMode.touch
                      ? t('Dokunmatik: dokunduğun yere tıklar', 'Touch: clicks where you tap')
                      : t('Touchpad: parmağınla imleci kaydır', 'Trackpad: slide to move the pointer'));
                },
              ),
              btn(Icons.fit_screen_rounded, t('Ekrana sığdır', 'Fit to screen'), () => setState(() {
                    _zoom = 1;
                    _pan = Offset.zero;
                  })),
              if (app.settings['sound'] != false)
                btn(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    _muted ? t('Sesi aç', 'Unmute') : t('Sessiz', 'Mute'), () {
                  setState(() => _muted = !_muted);
                  app.settings['muted'] = _muted;
                  Backend.fire('setMuted', {'muted': _muted});
                }, active: _muted),
              btn(_paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  _paused ? t('Devam et', 'Resume') : t('Duraklat', 'Pause'), () async {
                await _qmp(_paused ? 'cont' : 'stop');
                if (mounted) setState(() => _paused = !_paused);
              }, active: _paused),
            ]),
              ),
            ),
              PopupMenuButton<String>(
                tooltip: t('Diğer', 'More'),
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                onSelected: _menuAction,
                itemBuilder: (_) => [
                  _mi('cad', Icons.keyboard_alt_outlined, 'Ctrl + Alt + Del'),
                  _mi('shot', Icons.photo_camera_outlined, t('Ekran görüntüsü', 'Screenshot')),
                  _mi('cd', Icons.album_outlined, t('CD değiştir', 'Change CD')),
                  _mi('eject', Icons.eject_outlined, t('CD\'yi çıkar', 'Eject CD')),
                  _mi('paste', Icons.content_paste_rounded, t('Panodan yaz', 'Type clipboard')),
                  if (widget.vm.clipboard && clipboardCapable(widget.vm))
                    _mi('clip', Icons.content_paste_go_rounded, t('Panoyu VM\'e gönder', 'Send clipboard to VM')),
                  _mi('rotate', Icons.screen_rotation_rounded,
                      _landscape ? t('Yatay kilidi kaldır', 'Unlock rotation') : t('Yatay ekrana kilitle', 'Lock landscape')),
                  _mi('log', Icons.receipt_long_outlined, t('Günlük', 'Log')),
                  const PopupMenuDivider(),
                  _mi('save', Icons.save_alt_rounded, t('Durumu kaydet ve kapat', 'Save state and close')),
                  _mi('reset', Icons.restart_alt_rounded, t('Yeniden başlat', 'Restart')),
                  _mi('acpi', Icons.power_settings_new_rounded, t('Kapat (ACPI)', 'Shut down (ACPI)')),
                  _mi('kill', Icons.dangerous_outlined, t('Zorla kapat', 'Force stop')),
                ],
              ),
              Container(width: 1, height: 24, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 2)),
              IconButton(
                tooltip: t('Menüyü gizle', 'Hide menu'),
                onPressed: _hideToolbar,
                icon: const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white),
              ),
          ]),
        ),
      ),
    );
  }

  PopupMenuItem<String> _mi(String v, IconData i, String label) => PopupMenuItem(
        value: v,
        child: Row(children: [
          Icon(i, size: 20),
          const SizedBox(width: 12),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ]),
      );

  Widget _keyBarWidget() {
    Widget k(String label, VoidCallback onTap, {bool active = false, double minW = 44}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
          child: Material(
            color: active ? const Color(0xFF7C5CFF) : const Color(0xFF22264A),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                HapticFeedback.selectionClick();
                onTap();
              },
              child: Container(
                constraints: BoxConstraints(minWidth: minW),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                child: Text(label,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5)),
              ),
            ),
          ),
        );
    Widget mod(String label, int ks) => k(label, () => _toggleSticky(ks), active: _sticky.contains(ks));

    return Container(
      color: const Color(0xFF0E1024),
      height: 50,
      child: SafeArea(
        top: false,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 6), children: [
          k('Esc', () => _tap(Ks.esc)),
          k('Tab', () => _tap(Ks.tab)),
          mod('Ctrl', Ks.ctrlL),
          mod('Alt', Ks.altL),
          mod('Shift', Ks.shiftL),
          mod('Win', Ks.superL),
          k('←', () => _tap(Ks.left)),
          k('↑', () => _tap(Ks.up)),
          k('↓', () => _tap(Ks.down)),
          k('→', () => _tap(Ks.right)),
          k('Enter', () => _tap(Ks.enter)),
          k('Del', () => _tap(Ks.del)),
          k('Home', () => _tap(Ks.home)),
          k('End', () => _tap(Ks.end)),
          k('PgUp', () => _tap(Ks.pgUp)),
          k('PgDn', () => _tap(Ks.pgDn)),
          k('Ins', () => _tap(Ks.ins)),
          for (var i = 0; i < 12; i++) k('F${i + 1}', () => _tap(Ks.f1 + i)),
          k('PrtSc', () => _tap(Ks.printScreen)),
          k('Ctrl+Alt+Del', () => _combo([Ks.ctrlL, Ks.altL], Ks.del)),
        ]),
      ),
    );
  }
}
