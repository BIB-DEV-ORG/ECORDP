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

import '../widgets/ecordp_liquid.dart';
import '../widgets/ecordp_style.dart';

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
        state.value = gFFI.serverModel.clients.isNotEmpty
            ? EcoSupportState.live
            : EcoSupportState.ready;
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

/// Écran affiché à la personne aidée.
class EcoSupportPage extends StatefulWidget {
  const EcoSupportPage({Key? key}) : super(key: key);

  @override
  State<EcoSupportPage> createState() => _EcoSupportPageState();
}

class _EcoSupportPageState extends State<EcoSupportPage>
    with SingleTickerProviderStateMixin {
  final s = EcoSupport.instance;
  final _code = TextEditingController();
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
        ..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    _code.dispose();
    super.dispose();
  }

  String get _techName => s.tech.value.isEmpty ? 'Votre technicien' : s.tech.value;

  Widget _logo() {
    return SizedBox(
      width: 150,
      height: 150,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) => Stack(alignment: Alignment.center, children: [
          for (final shift in [0.0, 0.5])
            Builder(builder: (_) {
              final t = (_pulse.value + shift) % 1;
              return Transform.scale(
                scale: 0.6 + t,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kEcoCoral.withOpacity(0.35 * (1 - t)),
                  ),
                ),
              );
            }),
          child!,
        ]),
        child: ClipRRect(
            borderRadius: BorderRadius.circular(28), child: loadIcon(96)),
      ),
    );
  }

  Widget _codeTiles(EcoLiquid l) {
    final c = s.code.value;
    if (c.length != 6) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (final part in [c.substring(0, 2), c.substring(2, 4), c.substring(4)])
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: l.fill, borderRadius: BorderRadius.circular(12)),
          child: Text(part,
              style: TextStyle(
                  fontFamily: kEcoMono, fontSize: 22, color: l.text)),
        ),
    ]);
  }

  Widget _body(BuildContext context, EcoLiquid l) {
    final sub = TextStyle(fontFamily: kEcoInter, fontSize: 15, color: l.sub, height: 1.5);
    switch (s.state.value) {
      case EcoSupportState.starting:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          _logo(),
          Text('Connexion au service d’aide…', style: sub),
        ]);
      case EcoSupportState.needCode:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(borderRadius: BorderRadius.circular(20), child: loadIcon(72)),
          const SizedBox(height: 18),
          Text('Votre code d’aide', style: ecoTitle(context, size: 30)),
          const SizedBox(height: 6),
          Text('Saisissez le code donné par votre technicien.', style: sub),
          const SizedBox(height: 18),
          SizedBox(
            width: 260,
            child: TextField(
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
          ),
          const SizedBox(height: 8),
          Obx(() => Text(s.error.value,
              style: const TextStyle(color: Color(0xFFD9432A), fontWeight: FontWeight.w600))),
          const SizedBox(height: 8),
          EcoGradientButton(label: 'Valider', onPressed: () => s.submitCode(_code.text)),
        ]);
      case EcoSupportState.ready:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          _logo(),
          Text('$_techName arrive', style: ecoTitle(context, size: 34)),
          const SizedBox(height: 8),
          Text('Votre session d’aide est prête.\nGardez cette fenêtre ouverte.',
              textAlign: TextAlign.center, style: sub),
          const SizedBox(height: 18),
          _codeTiles(l),
        ]);
      case EcoSupportState.live:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
                color: kEcoCoral.withOpacity(0.16),
                borderRadius: BorderRadius.circular(999)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              EcoLiveDot(color: kEcoCoral),
              SizedBox(width: 8),
              Text('En direct',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: Color(0xFFD9532F))),
            ]),
          ),
          const SizedBox(height: 18),
          Text('$_techName vous aide\nen ce moment',
              textAlign: TextAlign.center, style: ecoTitle(context, size: 34)),
          const SizedBox(height: 8),
          Text('Il voit votre écran et peut utiliser la souris.\nNe fermez pas cette fenêtre.',
              textAlign: TextAlign.center, style: sub),
        ]);
      case EcoSupportState.keepAsked:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(borderRadius: BorderRadius.circular(20), child: loadIcon(72)),
          const SizedBox(height: 18),
          Text('Garder l’accès ?',
              textAlign: TextAlign.center, style: ecoTitle(context, size: 32)),
          const SizedBox(height: 8),
          Text(
              '$_techName souhaite pouvoir vous aider plus tard\nsans nouveau code. EcoRDP sera installé sur cet ordinateur.',
              textAlign: TextAlign.center,
              style: sub),
          const SizedBox(height: 20),
          Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton(onPressed: s.declineKeep, child: const Text('Non merci')),
            const SizedBox(width: 12),
            EcoGradientButton(label: 'Autoriser', onPressed: s.acceptKeep),
          ]),
        ]);
      case EcoSupportState.kept:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(borderRadius: BorderRadius.circular(20), child: loadIcon(72)),
          const SizedBox(height: 18),
          Text('Accès permanent activé',
              textAlign: TextAlign.center, style: ecoTitle(context, size: 30)),
          const SizedBox(height: 8),
          Text('Terminez l’installation dans la fenêtre qui s’ouvre.\n$_techName pourra se connecter quand vous le souhaitez.',
              textAlign: TextAlign.center, style: sub),
        ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = EcoLiquid.of(context);
    return Stack(children: [
      const Positioned.fill(child: EcoMeshBackground()),
      Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: EcoGlassCard(
              padding: const EdgeInsets.fromLTRB(28, 30, 28, 24),
              child: Obx(() => Column(mainAxisSize: MainAxisSize.min, children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 450),
                      switchInCurve: Curves.easeOutCubic,
                      transitionBuilder: (child, a) => FadeTransition(
                          opacity: a,
                          child: ScaleTransition(
                              scale: Tween(begin: 0.96, end: 1.0).animate(a),
                              child: child)),
                      child: KeyedSubtree(
                          key: ValueKey(s.state.value), child: _body(context, l)),
                    ),
                    if (s.state.value != EcoSupportState.kept) ...[
                      const SizedBox(height: 26),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => s.stop(),
                          style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(50)),
                          child: const Text('Arrêter l’aide',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ])),
            ),
          ),
        ),
      ),
    ]);
  }
}
