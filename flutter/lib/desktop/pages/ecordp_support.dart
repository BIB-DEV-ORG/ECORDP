// EcoRDP Aide : lancé depuis le fichier téléchargé sur rdp.eco-hub.fr, EcoRDP devient un petit
// utilitaire : le code de session, « Démarrer la session », une discussion avec le technicien
// et les explications. Rien n'est transmis au technicien avant le clic sur Démarrer.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:window_manager/window_manager.dart';

import '../widgets/ecordp_liquid.dart';
import '../widgets/ecordp_style.dart';
import '../widgets/ecordp_window.dart';

const kEcoSupportApi = 'https://rdp.eco-hub.fr/aide/api';

enum EcoSupportState { starting, needCode, found, ready, live, keepAsked, kept }

class EcoChatMessage {
  final bool mine;
  final String text;
  final DateTime at;
  EcoChatMessage(this.mine, this.text, this.at);
}

class EcoSupport {
  EcoSupport._();
  static final EcoSupport instance = EcoSupport._();

  final active = false.obs;
  final state = EcoSupportState.starting.obs;
  final tech = ''.obs;
  final code = ''.obs;
  final error = ''.obs;
  final busy = false.obs;
  final messages = <EcoChatMessage>[].obs;
  Timer? _beat;
  Timer? _chatTimer;
  DateTime? liveSince;
  String? _keptPassword;
  // Secret de session renvoyé par le service d'aide : prouve que c'est bien ce PC
  String _secret = '';
  bool _keepDeclined = false;

  /// Lancé depuis le fichier d'aide (rdp.eco-hub.exe, ou l'image disque sur Mac).
  static bool get candidate {
    if (!(isWindows || isMacOS)) return false;
    final launched =
        Platform.environment['RUSTDESK_APPNAME'] ?? Platform.resolvedExecutable;
    final name = launched.split(RegExp(r'[\\/]')).last.toLowerCase();
    if (name.startsWith('rdp.eco-hub')) return true;
    return isMacOS && !bind.mainIsInstalled() && launched.startsWith('/Volumes/');
  }

  /// Au lancement : mode aide si lancé depuis le fichier d'aide, ou sur un Mac sans service
  /// installé qui vient de télécharger une session (app glissée dans Applications).
  static Future<void> autoStart() async {
    if (candidate) return instance.start();
    if (!isMacOS || bind.mainIsInstalledDaemon(prompt: false)) return;
    try {
      final j = await instance._post('lookup', {});
      instance._found(j);
      await instance.start(lookedUp: true);
    } catch (_) {}
  }

  Future<void> start({bool lookedUp = false}) async {
    if (active.value) return;
    active.value = true;
    await windowManager.setMinimumSize(const Size(760, 520));
    await windowManager.setSize(const Size(860, 560));
    await windowManager.center();
    if (!bind.mainIsInstalled()) {
      await bind.mainSetOption(key: 'temporary-password-length', value: '10');
      await bind.mainSetOption(
          key: kOptionVerificationMethod, value: kUseTemporaryPassword);
      // Le clic sur « Démarrer la session » vaut accord : pas de seconde validation.
      await bind.mainSetOption(key: kOptionApproveMode, value: 'password');
    } else {
      // EcoRDP déjà installé (accès gardé…) : on n'enlève rien, on ajoute seulement
      // le mot de passe temporaire et l'entrée par mot de passe s'ils manquent.
      if (bind.mainGetOptionSync(key: kOptionVerificationMethod) ==
          kUsePermanentPassword) {
        await bind.mainSetOption(
            key: kOptionVerificationMethod, value: kUseBothPasswords);
      }
      if (bind.mainGetOptionSync(key: kOptionApproveMode) == 'click') {
        await bind.mainSetOption(key: kOptionApproveMode, value: '');
      }
    }
    await bind.mainUpdateTemporaryPassword();
    if (!lookedUp) await lookup('');
  }

  void _found(Map<String, dynamic> j) {
    code.value = '${j['code']}';
    tech.value = '${j['tech'] ?? ''}';
    state.value = EcoSupportState.found;
  }

  /// Retrouve la session (par l'adresse du téléchargement, ou par le code saisi) sans rien transmettre.
  Future<bool> lookup(String c) async {
    error.value = '';
    try {
      _found(await _post('lookup', {'code': c}));
      return true;
    } catch (e) {
      state.value = EcoSupportState.needCode;
      if (c.isNotEmpty) error.value = e == 'no_session' ? 'Code inconnu ou expiré.' : '$e';
      return false;
    }
  }

  /// Code saisi à la main : on le vérifie puis on démarre directement.
  Future<void> submitCode(String c) async {
    final digits = c.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 6) {
      error.value = 'Le code fait 6 chiffres.';
      return;
    }
    busy.value = true;
    try {
      if (await lookup(digits)) await begin();
    } finally {
      busy.value = false;
    }
  }

  Future<Map<String, String>> _credentials() async {
    for (var i = 0; i < 60; i++) {
      final id = await bind.mainGetMyId();
      final pw = _keptPassword ?? await bind.mainGetTemporaryPassword();
      if (id.isNotEmpty && pw.isNotEmpty) return {'id': id, 'password': pw};
      await Future.delayed(const Duration(milliseconds: 500));
    }
    throw 'Identifiant indisponible';
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final r = await http
        .post(Uri.parse('$kEcoSupportApi/$path'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode != 200) throw j['error'] ?? 'Erreur ${r.statusCode}';
    return j;
  }

  /// « Démarrer la session » : l'ordinateur s'annonce et le technicien peut se connecter.
  Future<void> begin() async {
    error.value = '';
    busy.value = true;
    try {
      final os = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
      final j = await _post('announce', {
        ...await _credentials(),
        'code': code.value,
        'hostname': Platform.localHostname,
        'os': os.length > 60 ? os.substring(0, 60) : os,
      });
      code.value = '${j['code']}';
      _secret = '${j['secret'] ?? ''}';
      tech.value = '${j['tech'] ?? ''}';
      state.value = EcoSupportState.ready;
      _beat?.cancel();
      _beat = Timer.periodic(const Duration(seconds: 10), (_) => _heartbeat());
      _chatTimer?.cancel();
      _chatTimer = Timer.periodic(
          const Duration(seconds: 3), (_) => _pullChat().catchError((_) {}));
      _pullChat().catchError((_) {});
    } catch (e) {
      error.value = '$e';
    } finally {
      busy.value = false;
    }
  }

  bool get started =>
      state.value != EcoSupportState.starting &&
      state.value != EcoSupportState.needCode &&
      state.value != EcoSupportState.found;

  Future<void> _pullChat([String text = '']) async {
    if (_secret.isEmpty) return;
    final j = await _post('chat', {
      'code': code.value,
      'secret': _secret,
      'id': await bind.mainGetMyId(),
      if (text.isNotEmpty) 'text': text,
    });
    final list = (j['messages'] as List? ?? []).map((m) => EcoChatMessage(
        m['from'] == 'peer',
        '${m['text']}',
        DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt())));
    final next = list.toList();
    if (next.length != messages.length) messages.assignAll(next);
  }

  Future<void> send(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    try {
      await _pullChat(t);
    } catch (_) {
      error.value = 'Message non envoyé, réessayez.';
    }
  }

  Future<void> _heartbeat() async {
    try {
      final j = await _post('heartbeat',
          {'code': code.value, 'secret': _secret, ...await _credentials()});
      if (j['ended'] == true) return stop(notify: false);
      final s = state.value;
      if (s == EcoSupportState.keepAsked || s == EcoSupportState.kept) return;
      if (j['keep'] == true && !_keepDeclined) {
        state.value = EcoSupportState.keepAsked;
      } else {
        final live = gFFI.serverModel.clients.isNotEmpty;
        if (live && liveSince == null) liveSince = DateTime.now();
        if (!live) liveSince = null;
        state.value = live ? EcoSupportState.live : EcoSupportState.ready;
      }
    } catch (_) {}
  }

  /// Accès permanent : mot de passe fort transmis au technicien, puis installation.
  Future<void> acceptKeep() async {
    const chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    final pw = List.generate(16, (_) => chars[rnd.nextInt(chars.length)]).join();
    if (!await bind.mainSetPermanentPasswordWithResult(password: pw)) {
      error.value = "Impossible d'enregistrer l'accès permanent.";
      return;
    }
    await bind.mainSetOption(
        key: kOptionVerificationMethod, value: kUseBothPasswords);
    _keptPassword = pw;
    state.value = EcoSupportState.kept;
    await _heartbeat();
    if (isWindows) bind.mainGotoInstall();
  }

  void declineKeep() {
    _keepDeclined = true;
    state.value = EcoSupportState.ready;
  }

  Future<void> stop({bool notify = true}) async {
    _beat?.cancel();
    _chatTimer?.cancel();
    if (notify && _secret.isNotEmpty) {
      try {
        await _post('end', {
          'code': code.value,
          'secret': _secret,
          'id': await bind.mainGetMyId()
        });
      } catch (_) {}
    }
    exit(0);
  }
}

/// L'utilitaire affiché à la personne aidée : session à gauche, discussion et explications à droite.
class EcoSupportPage extends StatefulWidget {
  const EcoSupportPage({Key? key}) : super(key: key);

  @override
  State<EcoSupportPage> createState() => _EcoSupportPageState();
}

class _EcoSupportPageState extends State<EcoSupportPage>
    with SingleTickerProviderStateMixin {
  final s = EcoSupport.instance;
  final _code = TextEditingController();
  final _msg = TextEditingController();
  final _scroll = ScrollController();
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2200))
    ..repeat();
  Timer? _tick;
  StreamSubscription? _msgSub;
  int _tab = 1;
  int _seenTech = 0;
  bool _macScreen = true, _macControl = true;

  @override
  void initState() {
    super.initState();
    // Compteur « en direct » et autorisations macOS rafraîchis chaque seconde
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (isMacOS) {
        _macScreen = bind.mainIsCanScreenRecording(prompt: false);
        _macControl = bind.mainIsProcessTrusted(prompt: false);
      }
      setState(() {});
    });
    _msgSub = s.messages.listen((list) {
      // Premier message du technicien : on bascule sur la discussion
      if (_techCount(list) > _seenTech && _tab != 0 && _seenTech == 0) {
        setState(() => _tab = 0);
      }
      if (_tab == 0) _seenTech = _techCount(list);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _msgSub?.cancel();
    _pulse.dispose();
    _code.dispose();
    _msg.dispose();
    _scroll.dispose();
    super.dispose();
  }

  int _techCount(List<EcoChatMessage> l) => l.where((m) => !m.mine).length;

  String get _tech => s.tech.value.trim();
  String get _techName => _tech.isEmpty ? 'Votre technicien' : _tech;

  String _elapsed() {
    final since = s.liveSince;
    if (since == null) return '00:00';
    final d = DateTime.now().difference(since);
    final m = d.inMinutes.toString().padLeft(2, '0');
    final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  Widget _avatar(EcoLiquid l, {required bool live, double size = 64}) {
    final initial = (_tech.isEmpty ? 'T' : _tech[0]).toUpperCase();
    return SizedBox(
      width: size * 1.7,
      height: size * 1.7,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) => Stack(alignment: Alignment.center, children: [
          for (final shift in [0.0, 0.5])
            Builder(builder: (_) {
              final t = (_pulse.value + shift) % 1;
              return Container(
                width: size + size * 0.7 * t,
                height: size + size * 0.7 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: l.accent.withOpacity((live ? 0.32 : 0.2) * (1 - t)),
                ),
              );
            }),
          child!,
        ]),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: l.dark ? l.fill : kEcoInk,
            border: Border.all(color: l.accent, width: 2.5),
          ),
          alignment: Alignment.center,
          child: Text(initial,
              style: TextStyle(
                  fontFamily: kEcoDisplay,
                  fontSize: size * 0.45,
                  color: l.dark ? l.text : EcoLiquid.cream,
                  shadows: l.glow)),
        ),
      ),
    );
  }

  Widget _title(BuildContext context, String t, {double size = 28}) => Text(t,
      textAlign: TextAlign.center, style: ecoTitle(context, size: size));

  Widget _sub(EcoLiquid l, String t) => Text(t,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 13.5, color: l.sub, height: 1.5));

  /// Le code en 6 cases, comme sur rdp.eco-hub.fr.
  Widget _codeBoxes(EcoLiquid l, String code, {double h = 52}) {
    Widget box(String d) => Container(
          width: h * 0.82,
          height: h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: l.dark ? l.fill : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: l.edge),
          ),
          child: Text(d,
              style: TextStyle(
                  fontFamily: kEcoMono,
                  fontSize: h * 0.5,
                  fontWeight: FontWeight.w600,
                  color: l.text,
                  shadows: l.glow)),
        );
    final c = code.padRight(6);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < 3; i++) ...[box(c[i]), const SizedBox(width: 6)],
      Container(
          width: 10,
          height: 3,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
              color: l.edge, borderRadius: BorderRadius.circular(2))),
      for (var i = 3; i < 6; i++) ...[box(c[i]), if (i < 5) const SizedBox(width: 6)],
    ]);
  }

  Widget _techChip(EcoLiquid l) => Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
        decoration: BoxDecoration(
          color: l.dark ? l.fill : Colors.white.withOpacity(0.7),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: l.dark ? l.card : kEcoInk),
            child: Text((_tech.isEmpty ? 'T' : _tech[0]).toUpperCase(),
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: l.dark ? l.text : EcoLiquid.cream)),
          ),
          const SizedBox(width: 8),
          Text('$_techName va vous aider',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: l.text)),
        ]),
      );

  Widget _error(EcoLiquid l) => s.error.value.isEmpty
      ? const SizedBox(height: 8)
      : Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(s.error.value,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFD9432A), fontWeight: FontWeight.w600)),
        );

  /// Mac : partage d'écran et contrôle à autoriser dans les Réglages.
  Widget _macPermissions(EcoLiquid l) {
    if (!isMacOS || (_macScreen && _macControl)) return const SizedBox.shrink();
    Widget row(String label, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            const Icon(Icons.error_outline_rounded, size: 18, color: Color(0xFFE59A1A)),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: l.text))),
            TextButton(onPressed: onTap, child: const Text('Autoriser')),
          ]),
        );
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 8),
      decoration: BoxDecoration(
          color: l.dark ? l.fill : Colors.white.withOpacity(0.7),
          borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!_macScreen)
          row('Partage de l’écran', () => bind.mainIsCanScreenRecording(prompt: true)),
        if (!_macControl)
          row('Contrôle de la souris', () => bind.mainIsProcessTrusted(prompt: true)),
      ]),
    );
  }

  Widget _sessionBody(BuildContext context, EcoLiquid l) {
    switch (s.state.value) {
      case EcoSupportState.starting:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          _avatar(l, live: false),
          const SizedBox(height: 6),
          _sub(l, 'Recherche de votre session…'),
        ]);
      case EcoSupportState.needCode:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          _title(context, 'Votre code'),
          const SizedBox(height: 6),
          _sub(l, 'Saisissez le code à 6 chiffres\ndonné par votre technicien.'),
          const SizedBox(height: 18),
          TextField(
            controller: _code,
            autofocus: true,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6)
            ],
            style: TextStyle(
                fontFamily: kEcoMono, fontSize: 30, letterSpacing: 10, color: l.text),
            decoration: InputDecoration(
              filled: true,
              fillColor: l.dark ? l.fill : Colors.white,
              hintText: '000000',
              hintStyle: TextStyle(color: l.sub.withOpacity(0.4)),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
            onSubmitted: (v) => s.submitCode(v),
          ),
          _error(l),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: EcoGradientButton(
                label: s.busy.value ? 'Connexion…' : 'Démarrer la session',
                icon: Icons.play_arrow_rounded,
                onPressed: () => s.busy.value ? null : s.submitCode(_code.text)),
          ),
        ]);
      case EcoSupportState.found:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          _techChip(l),
          const SizedBox(height: 20),
          Text('VOTRE CODE DE SESSION', style: ecoEyebrow(context)),
          const SizedBox(height: 10),
          _codeBoxes(l, s.code.value),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: EcoGradientButton(
                label: s.busy.value ? 'Connexion…' : 'Démarrer la session',
                icon: Icons.play_arrow_rounded,
                onPressed: () => s.busy.value ? null : s.begin()),
          ),
          _error(l),
          _sub(l, 'Rien n’est partagé avant ce clic.'),
          _macPermissions(l),
        ]);
      case EcoSupportState.ready:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          _avatar(l, live: false),
          _title(context, '$_techName arrive', size: 26),
          const SizedBox(height: 6),
          _sub(l, 'Session ouverte. Gardez cette fenêtre ouverte,\nil se connecte dans un instant.'),
          const SizedBox(height: 14),
          _codeBoxes(l, s.code.value, h: 36),
          _macPermissions(l),
        ]);
      case EcoSupportState.live:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          _avatar(l, live: true),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: l.accent.withOpacity(0.16),
                borderRadius: BorderRadius.circular(999)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              EcoLiveDot(color: l.accent),
              const SizedBox(width: 8),
              Text('En direct  ${_elapsed()}',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: l.accent,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
          const SizedBox(height: 12),
          _title(context, '$_techName vous aide', size: 26),
          const SizedBox(height: 6),
          _sub(l, 'Il voit votre écran et peut utiliser la souris.\nVous gardez la main à tout moment.'),
        ]);
      case EcoSupportState.keepAsked:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          _avatar(l, live: false),
          _title(context, 'Garder l’accès ?', size: 26),
          const SizedBox(height: 6),
          _sub(l,
              '$_techName souhaite pouvoir vous aider plus tard sans nouveau code.\nEcoRDP sera installé sur cet ordinateur.'),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: s.declineKeep,
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50), shape: const StadiumBorder()),
                child: const Text('Non merci'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: EcoGradientButton(label: 'Autoriser', onPressed: s.acceptKeep)),
          ]),
        ]);
      case EcoSupportState.kept:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          _avatar(l, live: false),
          _title(context, 'Accès activé', size: 26),
          const SizedBox(height: 6),
          _sub(l,
              'Terminez l’installation dans la fenêtre qui s’ouvre.\n$_techName pourra vous aider quand vous le souhaitez.'),
        ]);
    }
  }

  Widget _sessionCard(BuildContext context, EcoLiquid l, bool bubble) {
    final st = s.state.value;
    return EcoGlassCard(
      radius: 26,
      tint: EcoLiquid.peach.withOpacity(0.45),
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
      child: Column(children: [
        EcoMoveArea(
          child: Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(9), child: loadIcon(28)),
            const SizedBox(width: 10),
            Text('EcoRDP Aide', style: ecoTitle(context, size: 20)),
            const Spacer(),
            if (bubble)
              IconButton(
                tooltip: translate('Minimize'),
                icon: Icon(Icons.remove_rounded, color: l.sub, size: 20),
                onPressed: () => windowManager.minimize(),
              ),
          ]),
        ),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 380),
                switchInCurve: Curves.easeOutCubic,
                transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: ScaleTransition(
                        scale: Tween(begin: 0.96, end: 1.0).animate(a), child: child)),
                child: KeyedSubtree(key: ValueKey(st), child: _sessionBody(context, l)),
              ),
            ),
          ),
        ),
        if (st != EcoSupportState.kept)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => s.stop(),
              icon: Icon(s.started ? Icons.stop_circle_outlined : Icons.close_rounded,
                  size: 18),
              label: Text(s.started ? 'Arrêter l’aide' : 'Quitter',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                foregroundColor: s.started ? const Color(0xFFE0443E) : l.sub,
                side: BorderSide(
                    color: s.started
                        ? const Color(0xFFE0443E).withOpacity(0.45)
                        : l.edge),
                shape: const StadiumBorder(),
              ),
            ),
          ),
        const SizedBox(height: 8),
        ValueListenableBuilder<TextEditingValue>(
            valueListenable: gFFI.serverModel.serverId,
            builder: (_, v, __) => Text('ID ${v.text}',
                style: TextStyle(fontFamily: kEcoMono, fontSize: 11, color: l.sub))),
      ]),
    );
  }

  Widget _chat(BuildContext context, EcoLiquid l) {
    if (!s.started) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const EcoIconDot(Icons.chat_bubble_outline_rounded, size: 48),
          const SizedBox(height: 14),
          Text('Discussion avec $_techName',
              style: TextStyle(fontWeight: FontWeight.w600, color: l.text)),
          const SizedBox(height: 4),
          _sub(l, 'Elle s’ouvre dès que vous démarrez la session.'),
        ]),
      );
    }
    final list = s.messages;
    return Column(children: [
      Expanded(
        child: list.isEmpty
            ? Center(
                child: _sub(l,
                    'Écrivez à $_techName ici,\nmême pendant qu’il travaille sur votre écran.'))
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: list.length,
                itemBuilder: (_, i) => _bubble(l, list[i]),
              ),
      ),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _msg,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(
              hintText: 'Votre message…',
              filled: true,
              fillColor: l.fill,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(width: 8),
        EcoRoundButton(
          tooltip: 'Envoyer',
          size: 42,
          onPressed: _send,
          child: Icon(Icons.arrow_upward_rounded, color: l.onAccent, size: 20),
        ),
      ]),
    ]);
  }

  void _send() {
    final t = _msg.text;
    _msg.clear();
    s.send(t);
  }

  Widget _bubble(EcoLiquid l, EcoChatMessage m) {
    final time =
        '${m.at.hour.toString().padLeft(2, '0')}:${m.at.minute.toString().padLeft(2, '0')}';
    return Align(
      alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        decoration: BoxDecoration(
          color: m.mine ? l.accent : (l.dark ? l.fill : EcoLiquid.sky.withOpacity(0.55)),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(m.mine ? 16 : 4),
            bottomRight: Radius.circular(m.mine ? 4 : 16),
          ),
        ),
        child: Column(
            crossAxisAlignment: m.mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!m.mine)
                Text(_techName,
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700, color: l.text)),
              SelectableText(m.text,
                  style: TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: m.mine ? l.onAccent : l.text)),
              Text(time,
                  style: TextStyle(
                      fontSize: 10,
                      color: (m.mine ? l.onAccent : l.sub).withOpacity(0.7))),
            ]),
      ),
    );
  }

  Widget _help(BuildContext context, EcoLiquid l) {
    Widget step(IconData icon, Color tint, String title, String text) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: l.dark ? l.fill : tint.withOpacity(0.35),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            EcoIconDot(icon, size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: l.text)),
                const SizedBox(height: 2),
                Text(text, style: TextStyle(fontSize: 13, color: l.sub, height: 1.45)),
              ]),
            ),
          ]),
        );
    return ListView(padding: const EdgeInsets.only(top: 4), children: [
      step(Icons.pin_outlined, EcoLiquid.peach, 'Votre code',
          'Il relie cet ordinateur à la session ouverte par votre technicien.'),
      step(Icons.play_arrow_rounded, EcoLiquid.sky, 'Démarrer la session',
          'Rien n’est partagé avant ce clic. Ensuite, votre technicien voit votre écran et peut utiliser la souris.'),
      step(Icons.chat_bubble_outline_rounded, EcoLiquid.mint, 'Discutez',
          'Écrivez-lui dans l’onglet Discussion, à tout moment.'),
      step(Icons.front_hand_outlined, EcoLiquid.butter, 'Vous gardez la main',
          '« Arrêter l’aide » coupe tout immédiatement. Rien n’est installé : fermer EcoRDP suffit.'),
      if (isMacOS)
        step(Icons.desktop_mac_outlined, EcoLiquid.pink, 'Sur Mac',
            'Autorisez « Enregistrement de l’écran » et « Accessibilité » quand macOS le demande, sinon votre technicien ne verra rien.'),
    ]);
  }

  Widget _sideCard(BuildContext context, EcoLiquid l) {
    final unread = _tab == 0 ? 0 : _techCount(s.messages) - _seenTech;
    return EcoGlassCard(
      radius: 26,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        EcoMoveArea(
          child: EcoSegmented(
            labels: [unread > 0 ? 'Discussion ($unread)' : 'Discussion', 'Comment ça marche'],
            index: _tab,
            onChanged: (i) => setState(() {
              _tab = i;
              if (i == 0) _seenTech = _techCount(s.messages);
            }),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(child: _tab == 0 ? _chat(context, l) : _help(context, l)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = EcoLiquid.of(context);
    final bubble = ecoBubbleWindow;
    final body = Obx(() {
      // Valeurs lues ici pour que l'Obx suive l'état, le code, l'erreur et la discussion
      s.state.value;
      s.code.value;
      s.error.value;
      s.busy.value;
      s.messages.length;
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: 360, child: _sessionCard(context, l, bubble)),
        const SizedBox(width: 12),
        Expanded(child: _sideCard(context, l)),
      ]);
    });
    // En bulle : seules les cartes sont visibles, avec une petite marge pour leur ombre
    return bubble
        ? Padding(padding: const EdgeInsets.all(8), child: body)
        : Stack(children: [
            const Positioned.fill(child: EcoMeshBackground()),
            Padding(padding: const EdgeInsets.all(14), child: body),
          ]);
  }
}
