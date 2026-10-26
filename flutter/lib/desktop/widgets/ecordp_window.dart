// EcoRDP « bulle » : sous Windows, la fenêtre principale n'a ni cadre ni fond ; seules les
// cartes de l'accueil sont visibles. Les boutons de fenêtre passent dans la carte de connexion.
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

import 'ecordp_liquid.dart';

/// Fenêtre principale Windows (hors mode « réception seule »).
bool get ecoBubbleWindow =>
    isWindows && desktopType == DesktopType.main && !bind.isIncomingOnly();

/// Bulle active : seul l'accueil est ouvert (les réglages gardent un fond et la barre d'onglets).
/// À lire dans un Obx pour suivre l'ouverture des onglets.
bool ecoBubbleNow() {
  if (!ecoBubbleWindow || !Get.isRegistered<DesktopTabController>()) return false;
  return Get.find<DesktopTabController>().state.value.tabs.length == 1;
}

/// Retire cadre et ombre système, qui dessineraient un rectangle autour de la bulle.
Future<void> ecoApplyBubbleFrame() async {
  if (!ecoBubbleWindow) return;
  await windowManager.setAsFrameless();
  await windowManager.setHasShadow(false);
}

class _EcoWinButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;
  const _EcoWinButton(this.icon, this.tooltip, this.onTap, {this.danger = false});

  @override
  State<_EcoWinButton> createState() => _EcoWinButtonState();
}

class _EcoWinButtonState extends State<_EcoWinButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final l = EcoLiquid.of(context);
    const red = Color(0xFFE0443E);
    final bg = widget.danger
        ? Color.lerp(l.fill, red, _hover ? 0.9 : 0.18)!
        : (_hover ? l.thumb : l.fill);
    final fg = widget.danger ? (_hover ? Colors.white : red) : l.sub;
    return Tooltip(
      message: translate(widget.tooltip),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 30,
            height: 30,
            decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
            child: Icon(widget.icon, size: 15, color: fg),
          ),
        ),
      ),
    );
  }
}

/// Menu, réduire, agrandir, fermer : uniquement quand la bulle est active.
class EcoWindowControls extends StatelessWidget {
  const EcoWindowControls({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Hors bulle, l'Obx ne lirait aucune valeur observée et GetX lèverait une erreur (écran gris)
    if (!ecoBubbleWindow) return const SizedBox.shrink();
    return Obx(() {
      if (!ecoBubbleNow()) return const SizedBox.shrink();
      return Row(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 8),
        if (!bind.isDisableSettings())
          _EcoWinButton(Icons.menu_rounded, 'Settings', DesktopTabPage.onAddSetting),
        const SizedBox(width: 6),
        _EcoWinButton(Icons.remove_rounded, 'Minimize', () => windowManager.minimize()),
        const SizedBox(width: 6),
        _EcoWinButton(
            stateGlobal.isMaximized.isTrue
                ? Icons.filter_none_rounded
                : Icons.crop_square_rounded,
            stateGlobal.isMaximized.isTrue ? 'Restore' : 'Maximize',
            () => toggleMaximize(true)),
        const SizedBox(width: 6),
        _EcoWinButton(Icons.close_rounded, 'Close', () => windowManager.close(),
            danger: true),
      ]);
    });
  }
}

/// Zone qui déplace la fenêtre quand la bulle est active (double-clic : agrandir).
class EcoMoveArea extends StatelessWidget {
  final Widget child;
  const EcoMoveArea({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) =>
      ecoBubbleWindow ? DragToMoveArea(child: child) : child;
}

/// Pastille d'état « Prêt » / « Connexion... » posée sous les cartes.
class EcoStatusPill extends StatelessWidget {
  const EcoStatusPill({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l = EcoLiquid.of(context);
    final stopped = Get.find<RxBool>(tag: 'stop-service');
    return Obx(() {
      final s = stateGlobal.svcStatus.value;
      final Color dot;
      final String text;
      if (stopped.value) {
        dot = kColorWarn;
        text = translate('Service is not running');
      } else if (s == SvcStatus.ready) {
        dot = const Color(0xFF32BEA6);
        text = translate('Ready');
      } else if (s == SvcStatus.connecting) {
        dot = kColorWarn;
        text = translate('connecting_status');
      } else {
        dot = const Color(0xFFE04F5F);
        text = translate('not_ready_status');
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: l.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: l.dark ? l.edgeHi : l.edge),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: dot)),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(fontSize: 13, color: l.text)),
        ]),
      );
    });
  }
}
