// EcoRDP Aide express côté technicien : créer un code de session, suivre les sessions en
// direct et se connecter en un clic (ID et mot de passe fournis par le service d'aide).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart' hide Dialog;
import 'package:flutter_hbb/common/widgets/login.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:http/http.dart' as http;

import '../widgets/ecordp_liquid.dart';
import '../widgets/ecordp_style.dart';
import 'ecordp_support.dart';

/// Carte d'accès rapide posée sur l'accueil.
class EcoHelpdeskCard extends StatelessWidget {
  const EcoHelpdeskCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l = EcoLiquid.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => showEcoHelpdesk(context),
        child: Container(
          margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            color: l.dark ? l.fill : kEcoInk,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(children: [
            const Icon(Icons.support_agent_rounded, color: kEcoCoral, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Aide express',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: l.dark ? l.text : const Color(0xFFFFEFDA))),
                Text('Créer un code pour dépanner',
                    style: TextStyle(
                        fontSize: 12,
                        color: (l.dark ? l.text : const Color(0xFFFFEFDA))
                            .withOpacity(0.65))),
              ]),
            ),
            Icon(Icons.arrow_forward_rounded,
                size: 18, color: l.dark ? l.text : const Color(0xFFFFEFDA)),
          ]),
        ),
      ),
    );
  }
}

Future<void> showEcoHelpdesk(BuildContext context) => showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (_) => const _EcoHelpdeskDialog(),
    );

class _Session {
  final Map<String, dynamic> raw;
  _Session(this.raw);
  String get code => '${raw['code']}';
  String get name => '${raw['name'] ?? ''}';
  String get status => '${raw['status'] ?? ''}';
  bool get keep => raw['keep'] == true;
  bool get ended => raw['ended'] == true;
  Map<String, dynamic>? get peer => raw['peer'] as Map<String, dynamic>?;
}

class _EcoHelpdeskDialog extends StatefulWidget {
  const _EcoHelpdeskDialog();

  @override
  State<_EcoHelpdeskDialog> createState() => _EcoHelpdeskDialogState();
}

class _EcoHelpdeskDialogState extends State<_EcoHelpdeskDialog> {
  final _name = TextEditingController();
  List<_Session> _sessions = [];
  String? _newCode;
  String _error = '';
  bool _needLogin = false;
  bool _busy = false;
  Timer? _timer;

  String get _token => bind.mainGetLocalOption(key: 'access_token');

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _name.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _call(String path, [Map<String, dynamic>? body]) async {
    final uri = Uri.parse('$kEcoSupportApi/$path');
    final headers = {
      'authorization': 'Bearer $_token',
      'content-type': 'application/json'
    };
    final r = body == null
        ? await http.get(uri, headers: headers).timeout(const Duration(seconds: 10))
        : await http
            .post(uri, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 10));
    if (r.statusCode == 401) throw 'login';
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode != 200) throw j['error'] ?? 'Erreur ${r.statusCode}';
    return j;
  }

  Future<void> _refresh() async {
    if (_token.isEmpty) {
      if (mounted) setState(() => _needLogin = true);
      return;
    }
    try {
      final j = await _call('sessions');
      if (!mounted) return;
      setState(() {
        _needLogin = false;
        _sessions = (j['sessions'] as List)
            .map((e) => _Session(e as Map<String, dynamic>))
            .where((s) => !s.ended)
            .toList();
      });
    } catch (e) {
      if (mounted) setState(() => e == 'login' ? _needLogin = true : _error = '$e');
    }
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final j = await _call('sessions', {'name': _name.text.trim()});
      _newCode = '${j['code']}';
      _name.clear();
      await _refresh();
    } catch (e) {
      _error = e == 'login' ? 'Connecte-toi à ton compte EcoRDP.' : '$e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _act(String what, String code) async {
    try {
      await _call('sessions/$what', {'code': code});
      await _refresh();
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  void _connect(_Session s) {
    final p = s.peer;
    if (p == null) return;
    Navigator.of(context).pop();
    connect(context, '${p['id']}', password: '${p['password']}');
  }

  String _fmt(String c) => c.length == 6 ? '${c.substring(0, 3)} ${c.substring(3)}' : c;

  Widget _sessionTile(EcoLiquid l, _Session s) {
    final online = s.status == 'en ligne';
    final p = s.peer;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(color: l.fill, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: online ? const Color(0xFF34C759) : l.sub.withOpacity(0.5),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.name.isEmpty ? 'Session' : s.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w600, color: l.text)),
            Text(
                [
                  'Code ${_fmt(s.code)}',
                  s.status,
                  if (p != null && '${p['hostname']}'.isNotEmpty) '${p['hostname']}',
                  if (s.keep) 'accès gardé',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: l.sub)),
          ]),
        ),
        if (p != null) ...[
          if (!s.keep)
            TextButton(
                onPressed: () => _act('keep', s.code),
                child: const Text('Garder l’accès')),
          const SizedBox(width: 4),
          EcoGradientButton(
              label: translate('Connect'), height: 36, onPressed: () => _connect(s)),
        ],
        IconButton(
          tooltip: 'Terminer',
          icon: Icon(Icons.close_rounded, size: 18, color: l.sub),
          onPressed: () => _act('end', s.code),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = EcoLiquid.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
        child: EcoGlassCard(
          padding: const EdgeInsets.fromLTRB(22, 18, 14, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const EcoIconDot(Icons.support_agent_rounded, size: 34),
                const SizedBox(width: 12),
                Expanded(child: Text('Aide express', style: ecoTitle(context, size: 26))),
                IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: l.sub)),
              ]),
              const SizedBox(height: 14),
              if (_needLogin) ...[
                Text(
                    'Connecte-toi à ton compte EcoRDP pour créer des sessions d’aide.',
                    style: TextStyle(color: l.sub, height: 1.5)),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: EcoGradientButton(
                    label: translate('Login'),
                    onPressed: () async {
                      await loginDialog();
                      _refresh();
                    },
                  ),
                ),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _name,
                        onSubmitted: (_) => _create(),
                        decoration: InputDecoration(
                          hintText: 'Pour qui ? (ex : PC de Marc)',
                          filled: true,
                          fillColor: l.fill,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    EcoGradientButton(
                        label: _busy ? '…' : 'Créer un code',
                        height: 48,
                        onPressed: _busy ? () {} : _create),
                  ]),
                ),
                if (_newCode != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: l.dark ? l.fill : EcoLiquid.peach,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(children: [
                      Text(_fmt(_newCode!),
                          style: TextStyle(
                              fontFamily: kEcoMono,
                              fontSize: 34,
                              letterSpacing: 2,
                              color: l.text,
                              shadows: l.glow)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                            'Il va sur rdp.eco-hub.fr, tape ce code et lance le fichier.',
                            style: TextStyle(fontSize: 13, color: l.text, height: 1.4)),
                      ),
                      IconButton(
                        tooltip: translate('Copy'),
                        icon: Icon(Icons.copy_rounded, color: l.text),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(
                              text:
                                  'Va sur https://rdp.eco-hub.fr et tape le code $_newCode, puis lance le fichier téléchargé.'));
                          showToast(translate('Copied'));
                        },
                      ),
                    ]),
                  ),
                ],
                const SizedBox(height: 16),
                Text('SESSIONS', style: ecoEyebrow(context)),
                const SizedBox(height: 8),
                Flexible(
                  child: _sessions.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Text('Aucune session en cours.',
                              style: TextStyle(color: l.sub)),
                        )
                      : ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.only(right: 8),
                          children: [for (final s in _sessions) _sessionTile(l, s)],
                        ),
                ),
              ],
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error,
                      style: const TextStyle(color: Color(0xFFD9432A), fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
