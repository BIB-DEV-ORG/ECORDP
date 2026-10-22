// EcoRDP : briques visuelles de l'accueil (cartes, entrées animées, halo).
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';

const kEcoMono = 'JetBrainsMono';
const kEcoDisplay = 'Olivier';
const kEcoInk = Color(0xFF1C1410);
const kEcoCoral = Color(0xFFFB7D59);
const kEcoCream = Color(0xFFFFF4EA);
const kEcoLine = Color(0xFFF0E2D6);
const kEcoMint = Color(0xFFB7E4C7);
const kEcoPastels = [
  Color(0xFFB7E4C7),
  Color(0xFFF6D56A),
  Color(0xFFB3D6F5),
  Color(0xFFE2C6F0),
  Color(0xFFFFB3C0),
];

bool ecoIsDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

/// Carte arrondie de l'accueil (blanche en clair, brun chaud en sombre).
BoxDecoration ecoCardDecoration(BuildContext context, {Color? color}) {
  final dark = ecoIsDark(context);
  return BoxDecoration(
    color: color ?? (dark ? MyTheme.duskCard : Colors.white),
    borderRadius: BorderRadius.circular(28),
    border: color == null
        ? Border.all(color: dark ? const Color(0xFF3A2E27) : kEcoLine)
        : null,
    boxShadow: color == null && !dark
        ? [
            BoxShadow(
              color: kEcoInk.withOpacity(0.10),
              blurRadius: 32,
              offset: const Offset(0, 12),
              spreadRadius: -20,
            )
          ]
        : null,
  );
}

TextStyle ecoTitle(BuildContext context, {double size = 26, Color? color}) =>
    TextStyle(
      fontFamily: kEcoDisplay,
      fontSize: size,
      letterSpacing: 0.5,
      height: 1.1,
      color: color ?? Theme.of(context).textTheme.titleLarge?.color,
    );

/// Apparition en fondu + glissement, décalée par [delay].
class EcoEntrance extends StatelessWidget {
  final Widget child;
  final int delay;
  const EcoEntrance({Key? key, required this.child, this.delay = 0})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 700 + delay),
      curve: Interval(delay / (700 + delay), 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}

/// Halo corail qui dérive lentement derrière la carte de connexion.
class EcoGlow extends StatefulWidget {
  final double size;
  final Color color;
  final Duration period;
  const EcoGlow(
      {Key? key,
      this.size = 340,
      this.color = kEcoCoral,
      this.period = const Duration(seconds: 9)})
      : super(key: key);

  @override
  State<EcoGlow> createState() => _EcoGlowState();
}

class _EcoGlowState extends State<EcoGlow> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.period)
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(_c.value);
          return Transform.translate(
            offset: Offset(-30 * t, 18 * t),
            child: Transform.scale(scale: 1 + 0.12 * t, child: child),
          );
        },
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              widget.color.withOpacity(0.55),
              widget.color.withOpacity(0),
            ], stops: const [0, 0.65]),
          ),
        ),
      ),
    );
  }
}

/// Pastille verte qui pulse pour signaler « en ligne ».
class EcoLiveDot extends StatefulWidget {
  final Color color;
  final double size;
  const EcoLiveDot({Key? key, this.color = const Color(0xFF3FB36B), this.size = 8})
      : super(key: key);

  @override
  State<EcoLiveDot> createState() => _EcoLiveDotState();
}

class _EcoLiveDotState extends State<EcoLiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withOpacity(0.45 * (1 - _c.value)),
              spreadRadius: 8 * _c.value,
            )
          ],
        ),
      ),
    );
  }
}

/// Bouton pilule : plein (corail) ou contour.
class EcoPill extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool primary;
  final bool onDark;
  final double height;
  const EcoPill(
      {Key? key,
      required this.label,
      required this.onPressed,
      this.icon,
      this.primary = false,
      this.onDark = false,
      this.height = 38})
      : super(key: key);

  @override
  State<EcoPill> createState() => _EcoPillState();
}

class _EcoPillState extends State<EcoPill> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final dark = widget.onDark || ecoIsDark(context);
    final Color bg;
    final Color fg;
    final Color border;
    if (widget.primary) {
      bg = kEcoCoral;
      fg = kEcoInk;
      border = kEcoCoral;
    } else if (dark) {
      bg = _hover ? kEcoCream.withOpacity(0.10) : Colors.transparent;
      fg = kEcoCream.withOpacity(_hover ? 1 : 0.75);
      border = kEcoCream.withOpacity(0.18);
    } else {
      bg = _hover ? kEcoInk : kEcoCream;
      fg = _hover ? kEcoCream : kEcoInk;
      border = _hover ? kEcoInk : kEcoLine;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          height: widget.height,
          transform: Matrix4.translationValues(
              0, _hover && widget.primary ? -2 : 0, 0),
          padding: EdgeInsets.symmetric(horizontal: widget.height * 0.45),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
            boxShadow: _hover && widget.primary
                ? [
                    BoxShadow(
                        color: kEcoCoral.withOpacity(0.55),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                        spreadRadius: -8)
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.label,
                  style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w600,
                      fontSize: max(13, widget.height * 0.3))),
              if (widget.icon != null) ...[
                const SizedBox(width: 8),
                Icon(widget.icon, size: max(16, widget.height * 0.32), color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
