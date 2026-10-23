// EcoRDP Aide : lancé sous le nom rdp.eco-hub.exe (téléchargé depuis rdp.eco-hub.fr avec un
// code de session), EcoRDP s'annonce au service d'aide pour que le technicien se connecte sans
// saisir d'ID ni de mot de passe, et affiche un écran simple avec un bouton Arrêter.
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

enum EcoSupportState { starting, needCode, ready, live, keepAsked, kept }

class EcoSupport {
  EcoSupport._();
  static final EcoSupport instance = EcoSupport._();

  final active = false.obs;
  final state = EcoSupportState.starting.obs;
  final tech = ''.obs;
  final code = ''.obs;
  final error = ''.obs;
  Timer? _beat;
  DateTime? liveSince;
  String? _keptPassword;
  bool _keepDeclined = false;

  /// Lancé depuis le fichier d'aide, sans installation.
  static bool get candidate {
    if (!(isWindows || isMacOS) || bind.mainIsInstalled()) return false;
    final launched =
        Platform.environment['RUSTDESK_APPNAME'] ?? Platform.resolvedExecutable;
    final name = launched.split(RegExp(r'[\\/]')).last.toLowerCase();
    if (name.startsWith('rdp.eco-hub')) return true;
    // Mac : l'app est ouverte directement depuis l'image disque rdp.eco-hub.dmg
    return isMacOS && launched.startsWith('/Volumes/');
  }

  Future<void> start() async {
    if (active.value) return;
    active.value = true;
    // Petite fenêtre « bulle » centrée pour la personne aidée
    await windowManager.setMinimumSize(const Size(380, 560));
    await windowManager.setSize(const Size(420, 640));
    await windowManager.center();
    await bind.mainSetOption(key: 'temporary-password-length', value: '10');
    await bind.mainSetOption(
        key: kOptionVerificationMethod, value: kUseTemporaryPassword);
    // Le technicien entre avec le mot de passe transmis, sans clic d'acceptation.
    await bind.mainSetOption(key: kOptionApproveMode, value: 'password');
    await bind.mainUpdateTemporaryPassword();
    await _announce('');
  }

  Future<void> submitCode(String c) => _announce(c.replaceAll(RegExp(r'\D'), ''));

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

  Future<void> _announce(String c) async {
    error.value = '';
    try {
      final os = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
      final j = await _post('announce', {
        ...await _credentials(),
        'code': c,
        'hostname': Platform.localHostname,
        'os': os.length > 60 ? os.substring(0, 60) : os,
      });
      code.value = '${j['code']}';
      tech.value = '${j['tech'] ?? ''}';
      state.value = EcoSupportState.ready;
      _beat?.cancel();
      _beat = Timer.periodic(const Duration(seconds: 10), (_) => _heartbeat());
    } catch (e) {
      state.value = EcoSupportState.needCode;
      if (c.isNotEmpty) {
        error.value = e == 'no_session' ? 'Code inconnu ou expiré.' : '$e';
      }
    }
  }

  Future<void> _heartbeat() async {
    try {
      final j = await _post('heartbeat', {'code': code.value, ...await _credentials()});
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
    if (notify && code.value.isNotEmpty) {
      try {
        await _post('end', {'code': code.value, 'id': await bind.mainGetMyId()});
      } catch (_) {}
    }
    exit(0);
  }
}

/// Écran affiché à la personne aidée : petite bulle, avatar du technicien, étapes, Arrêter.
class EcoSupportPage extends StatefulWidget {
  const EcoSupportPage({Key? key}) : super(key: key);

  @override
  State<EcoSupportPage> createState() => _EcoSupportPageState();
}

class _EcoSupportPageState extends State<EcoSupportPage>
    with SingleTickerProviderStateMixin {
  final s = EcoSupport.instance;
  final _code = TextEditingController();
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2200))
    ..repeat();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Compteur « en direct » rafraîchi chaque seconde
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && s.state.value == EcoSupportState.live) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pulse.dispose();
    _code.dispose();
    super.dispose();
  }

  String get _tech => s.tech.value.trim();
  String get _techName => _tech.isEmpty ? 'Votre technicien' : _tech;

  String _elapsed() {
    final since = s.liveSince;
    if (since == null) return '';
    final d = DateTime.now().difference(since);
    final m = d.inMinutes.toString().padLeft(2, '0');
    final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  /// Avatar du technicien avec ondes qui pulsent.
  Widget _avatar(EcoLiquid l, {required bool live}) {
    final initial = (_tech.isEmpty ? 'T' : _tech[0]).toUpperCase();
    return SizedBox(
      width: 132,
      height: 132,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) => Stack(alignment: Alignment.center, children: [
          for (final shift in [0.0, 0.5])
            Builder(builder: (_) {
              final t = (_pulse.value + shift) % 1;
              return Container(
                width: 76 + 56 * t,
                height: 76 + 56 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: l.accent.withOpacity((live ? 0.32 : 0.22) * (1 - t)),
                ),
              );
            }),
          child!,
        ]),
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: l.dark ? l.fill : kEcoInk,
            border: Border.all(color: l.accent, width: 2.5),
          ),
          alignment: Alignment.center,
          child: Text(initial,
              style: TextStyle(
                  fontFamily: kEcoDisplay,
                  fontSize: 34,
                  color: l.dark ? l.text : const Color(0xFFFFEFDA),
                  shadows: l.glow)),
        ),
      ),
    );
  }

  Widget _stepRow(EcoLiquid l, String text, {required bool done, bool active = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? const Color(0xFF34C759) : (active ? l.accent : l.fill),
          ),
          child: Icon(done ? Icons.check_rounded : Icons.more_horiz_rounded,
              size: 14, color: done || active ? Colors.white : l.sub),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 13.5,
                  color: done || active ? l.text : l.sub,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
        ),
      ]),
    );
  }

  Widget _title(BuildContext context, String t) => Text(t,
      textAlign: TextAlign.center, style: ecoTitle(context, size: 30));

  Widget _sub(EcoLiquid l, String t) => Text(t,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 14, color: l.sub, height: 1.5));

  Widget _body(BuildContext context, EcoLiquid l) {
    switch (s.state.value) {
      case EcoSupportState.starting:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          _avatar(l, live: false),
          const SizedBox(height: 8),
          _sub(l, 'Connexion au service d’aide…'),
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
                fontFamily: kEcoMono, fontSize: 30, letterSpacing: 8, color: l.text),
            decoration: InputDecoration(
              filled: true,
              fillColor: l.fill,
              hintText: '000000',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none),
            ),
            onSubmitted: (v) => s.submitCode(v),
          ),
          const SizedBox(height: 8),
          Obx(() => Text(s.error.value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFFD9432A), fontWeight: FontWeight.w600))),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: EcoGradientButton(
                label: 'Valider', onPressed: () => s.submitCode(_code.text)),
          ),
        ]);
      case EcoSupportState.ready:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          _avatar(l, live: false),
          _title(context, '$_techName arrive'),
          const SizedBox(height: 6),
          _sub(l, 'Gardez cette fenêtre ouverte.'),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            decoration:
                BoxDecoration(color: l.fill, borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              _stepRow(l, 'Connecté au service d’aide', done: true),
              _stepRow(l, '$_techName est prévenu', done: true),
              _stepRow(l, 'En attente de sa connexion', done: false, active: true),
            ]),
          ),
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
          _title(context, '$_techName vous aide'),
          const SizedBox(height: 6),
          _sub(l, 'Il voit votre écran et peut utiliser la souris.\nVous gardez la main à tout moment.'),
        ]);
      case EcoSupportState.keepAsked:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          _avatar(l, live: false),
          _title(context, 'Garder l’accès ?'),
          const SizedBox(height: 6),
          _sub(l,
              '$_techName souhaite pouvoir vous aider plus tard sans nouveau code.\nEcoRDP sera installé sur cet ordinateur.'),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: s.declineKeep,
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
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
          _title(context, 'Accès activé'),
          const SizedBox(height: 6),
          _sub(l,
              'Terminez l’installation dans la fenêtre qui s’ouvre.\n$_techName pourra vous aider quand vous le souhaitez.'),
        ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = EcoLiquid.of(context);
    final bubble = ecoBubbleWindow;
    final card = EcoGlassCard(
      radius: 26,
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
      child: Obx(() => Column(children: [
            // En-tête déplaçable : logo, nom, réduire
            EcoMoveArea(
              child: Row(children: [
                ClipRRect(borderRadius: BorderRadius.circular(9), child: loadIcon(28)),
                const SizedBox(width: 10),
                Text('EcoRDP Aide',
                    style: TextStyle(fontWeight: FontWeight.w600, color: l.text)),
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
                    duration: const Duration(milliseconds: 420),
                    switchInCurve: Curves.easeOutCubic,
                    transitionBuilder: (child, a) => FadeTransition(
                        opacity: a,
                        child: ScaleTransition(
                            scale: Tween(begin: 0.96, end: 1.0).animate(a),
                            child: child)),
                    child: KeyedSubtree(
                        key: ValueKey(s.state.value), child: _body(context, l)),
                  ),
                ),
              ),
            ),
            if (s.state.value != EcoSupportState.kept) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => s.stop(),
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: const Text('Arrêter l’aide',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    foregroundColor: const Color(0xFFE0443E),
                    side: BorderSide(color: const Color(0xFFE0443E).withOpacity(0.45)),
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ValueListenableBuilder<TextEditingValue>(
                  valueListenable: gFFI.serverModel.serverId,
                  builder: (_, v, __) => Text('ID ${v.text}',
                      style: TextStyle(
                          fontFamily: kEcoMono, fontSize: 11.5, color: l.sub))),
            ],
          ])),
    );
    // En bulle : seule la carte est visible, avec une petite marge pour son ombre
    return bubble
        ? Padding(padding: const EdgeInsets.all(8), child: card)
        : Stack(children: [
            const Positioned.fill(child: EcoMeshBackground()),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440, maxHeight: 660),
                child: Padding(padding: const EdgeInsets.all(16), child: card),
              ),
            ),
          ]);
  }
}
