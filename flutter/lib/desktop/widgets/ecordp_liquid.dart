// EcoRDP : palette claire pastel / sombre noir, contrôles iOS et bascule de thème
// qui se répand comme un liquide depuis le bouton.
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_hbb/common.dart';

import 'ecordp_style.dart';

/// Palette EcoRDP. Clair : blanc chaud sobre, touches pastel EcoHub.
/// Sombre : noir pur, cartes anthracite à bord fin, texte blanc légèrement lumineux.
class EcoLiquid {
  final bool dark;
  final Color bg, card, text, sub, edge, edgeHi, fill, thumb, track, accent, onAccent;

  const EcoLiquid._(this.dark, this.bg, this.card, this.text, this.sub, this.edge,
      this.edgeHi, this.fill, this.thumb, this.track, this.accent, this.onAccent);

  static const light = EcoLiquid._(
    false,
    Color(0xFFF7F5F2), // fond
    Color(0xFFFFFFFF), // cartes
    Color(0xFF1C1410), // encre
    Color(0xFF7A6E66), // texte secondaire
    Color(0xFFECE8E3), // bordure
    Color(0xFFFFFFFF),
    Color(0xFFF2EFEB), // champs, segmenté
    Color(0xFFFFFFFF),
    Color(0xFFECE8E3),
    Color(0xFFFB7D59), // corail EcoHub
    Color(0xFF1C1410),
  );

  static const darkTheme = EcoLiquid._(
    true,
    Color(0xFF000000),
    Color(0xFF161618),
    Color(0xFFFFFFFF),
    Color(0xFF8E8E93),
    Color(0x17FFFFFF),
    Color(0x2EFFFFFF), // reflet du bord haut, façon verre
    Color(0xFF202023),
    Color(0xFF323236),
    Color(0x1AFFFFFF),
    Color(0xFFF0936A),
    Color(0xFF000000),
  );

  // Pastels EcoHub (thème clair) pour les pastilles et tuiles
  static const peach = Color(0xFFFFC4AE);
  static const pink = Color(0xFFFFB3C0);
  static const sky = Color(0xFFB3D6F5);
  static const butter = Color(0xFFF6D56A);
  static const mint = Color(0xFFB7E4C7);
  static const cream = Color(0xFFFFEFDA);

  static EcoLiquid of(BuildContext context) =>
      ecoIsDark(context) ? darkTheme : light;

  /// Léger halo blanc sur le texte en thème sombre.
  List<Shadow>? get glow => dark
      ? [Shadow(color: Colors.white.withOpacity(0.35), blurRadius: 10)]
      : null;
}

const kEcoInter = 'Inter';

TextStyle ecoEyebrow(BuildContext context) => TextStyle(
      fontFamily: kEcoInter,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.3,
      color: EcoLiquid.of(context).sub,
    );

/// Fond uni du thème.
class EcoMeshBackground extends StatelessWidget {
  const EcoMeshBackground({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: EcoLiquid.of(context).bg);
}

/// Pastille ronde sombre avec icône claire (style EcoHub).
class EcoIconDot extends StatelessWidget {
  final IconData icon;
  final double size;
  const EcoIconDot(this.icon, {Key? key, this.size = 40}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l = EcoLiquid.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: l.dark ? l.fill : l.text,
        border: l.dark ? Border.all(color: l.edgeHi) : null,
      ),
      child: Icon(icon,
          size: size * 0.48, color: l.dark ? l.text : const Color(0xFFFFEFDA)),
    );
  }
}

/// Carte unie à bord fin. [tint] : couleur pastel (thème clair seulement).
class EcoGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? tint;
  const EcoGlassCard(
      {Key? key,
      required this.child,
      this.padding = const EdgeInsets.all(20),
      this.radius = 22,
      this.tint})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l = EcoLiquid.of(context);
    final br = BorderRadius.circular(radius);
    if (l.dark) {
      // Liseré d'un pixel, plus clair en haut : bord de verre sur fond noir.
      return Container(
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          borderRadius: br,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [l.edgeHi, l.edge, l.edge],
            stops: const [0, 0.3, 1],
          ),
        ),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
              color: l.card, borderRadius: BorderRadius.circular(radius - 1)),
          child: child,
        ),
      );
    }
    final color = tint ?? l.card;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: br,
        border: Border.all(color: tint != null ? color : l.edge, width: 1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1C1410).withOpacity(0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
            spreadRadius: -12,
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Sélecteur segmenté façon iOS avec pastille glissante.
class EcoSegmented extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  const EcoSegmented(
      {Key? key,
      required this.labels,
      required this.index,
      required this.onChanged})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l = EcoLiquid.of(context);
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
          color: l.fill, borderRadius: BorderRadius.circular(12)),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / labels.length;
        return Stack(children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutBack,
            left: w * index,
            top: 0,
            bottom: 0,
            width: w,
            child: Container(
              decoration: BoxDecoration(
                color: l.thumb,
                borderRadius: BorderRadius.circular(9),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 3)),
                ],
              ),
            ),
          ),
          Row(children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(i),
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 250),
                        style: TextStyle(
                          fontFamily: kEcoInter,
                          fontSize: 13,
                          fontWeight:
                              i == index ? FontWeight.w600 : FontWeight.w500,
                          color: i == index ? l.text : l.sub,
                        ),
                        child: Text(labels[i],
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ]);
      }),
    );
  }
}

/// Bouton principal bombé, dégradé corail, qui rebondit.
class EcoGradientButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final double height;
  const EcoGradientButton(
      {Key? key,
      required this.label,
      required this.onPressed,
      this.icon,
      this.height = 52})
      : super(key: key);

  @override
  State<EcoGradientButton> createState() => _EcoGradientButtonState();
}

class _EcoGradientButtonState extends State<EcoGradientButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final l = EcoLiquid.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _down ? 0.95 : (_hover ? 1.03 : 1),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutBack,
          child: Container(
            height: widget.height,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: l.accent,
              boxShadow: [
                BoxShadow(
                  color: l.accent.withOpacity(
                      l.dark ? (_hover ? 0.45 : 0.25) : (_hover ? 0.4 : 0.2)),
                  blurRadius: _hover ? 26 : 18,
                  offset: Offset(0, l.dark ? 0 : 8),
                  spreadRadius: l.dark ? -4 : -8,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(widget.label,
                    style: TextStyle(
                        fontFamily: kEcoInter,
                        color: l.onAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                if (widget.icon != null) ...[
                  const SizedBox(width: 8),
                  Icon(widget.icon, color: l.onAccent, size: 18),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bouton rond en verre (recherche, bascule de thème...).
class EcoRoundButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onPressed;
  final String tooltip;
  final double size;
  const EcoRoundButton(
      {Key? key,
      required this.child,
      required this.onPressed,
      required this.tooltip,
      this.size = 44})
      : super(key: key);

  @override
  State<EcoRoundButton> createState() => _EcoRoundButtonState();
}

class _EcoRoundButtonState extends State<EcoRoundButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final l = EcoLiquid.of(context);
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: _hover ? 1.06 : 1,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _hover ? l.fill : l.card,
                border: Border.all(color: l.dark ? l.edgeHi : l.edge),
              ),
              child: IconTheme(
                data: IconThemeData(color: l.text, size: 19),
                child: Center(child: widget.child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Enveloppe la fenêtre : au changement de thème, l'ancien rendu est figé puis
/// « mangé » par une tache liquide qui part de [toggle]'s origine.
class EcoThemeReveal extends StatefulWidget {
  final Widget child;
  const EcoThemeReveal({Key? key, required this.child}) : super(key: key);

  static final GlobalKey<_EcoThemeRevealState> globalKey = GlobalKey();

  /// Bascule clair/sombre avec l'effet liquide, depuis le centre de [origin].
  static Future<void> toggle(BuildContext origin) async {
    final state = globalKey.currentState;
    final box = origin.findRenderObject() as RenderBox?;
    final dark = ecoIsDark(origin);
    final mode = dark ? ThemeMode.light : ThemeMode.dark;
    if (state == null || box == null) {
      await MyTheme.changeDarkMode(mode);
      return;
    }
    await state._run(box.localToGlobal(box.size.center(Offset.zero)), mode,
        dark ? EcoLiquid.light.bg : EcoLiquid.darkTheme.bg);
  }

  @override
  State<EcoThemeReveal> createState() => _EcoThemeRevealState();
}

class _EcoThemeRevealState extends State<EcoThemeReveal>
    with SingleTickerProviderStateMixin {
  final _boundary = GlobalKey();
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1150));
  ui.Image? _snapshot;
  Offset _origin = Offset.zero;
  Color _target = Colors.black;
  double _ratio = 1;

  Future<void> _run(Offset globalOrigin, ThemeMode mode, Color target) async {
    if (_c.isAnimating || _snapshot != null) return;
    final ro = _boundary.currentContext?.findRenderObject();
    final self = context.findRenderObject() as RenderBox?;
    if (ro is! RenderRepaintBoundary || self == null) {
      await MyTheme.changeDarkMode(mode);
      return;
    }
    _ratio = MediaQuery.of(context).devicePixelRatio;
    final image = await ro.toImage(pixelRatio: _ratio);
    setState(() {
      _snapshot = image;
      _origin = self.globalToLocal(globalOrigin);
      _target = target;
    });
    await MyTheme.changeDarkMode(mode);
    await _c.forward(from: 0);
    if (!mounted) return;
    setState(() => _snapshot = null);
    image.dispose();
  }

  @override
  void dispose() {
    _c.dispose();
    _snapshot?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        RepaintBoundary(key: _boundary, child: widget.child),
        if (snap != null)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => CustomPaint(
                  painter: _RevealPainter(
                      snap, _origin, _c.value, _ratio, _target),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RevealPainter extends CustomPainter {
  final ui.Image image;
  final Offset o;
  final double t;
  final double ratio;
  final Color target;
  _RevealPainter(this.image, this.o, this.t, this.ratio, this.target);

  static const _ease = Cubic(0.62, 0, 0.22, 1);

  Path _blob(double r, double amp, double phase) {
    const n = 12;
    final pts = List.generate(n, (i) {
      final a = i / n * 2 * pi;
      final k = 1 +
          amp * (sin(3 * a + phase) * 0.6 + sin(5 * a - phase * 1.7) * 0.4);
      return o + Offset(cos(a), sin(a)) * (r * k);
    });
    final p = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (var i = 0; i < n; i++) {
      final p0 = pts[(i - 1 + n) % n], p1 = pts[i];
      final p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n];
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      p.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final corners = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height)
    ];
    final far = corners.map((c) => (c - o).distance).reduce(max) * 1.15;
    final e = _ease.transform(t);
    final r = max(1.0, e * far);
    final amp = 0.22 * sin(pi * min(1, t * 1.4)) * (1 - t);

    // Ancien thème partout sauf dans la tache (qui révèle le nouveau).
    final hole = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addPath(_blob(r, amp, t * 4), Offset.zero);
    canvas.save();
    canvas.clipPath(hole);
    canvas.scale(1 / ratio);
    canvas.drawImage(image, Offset.zero, Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();

    // Gouttelettes projetées devant la vague.
    if (t < 0.8) {
      const drops = [
        (-2.6, 1.0, 11.0),
        (-2.2, 1.35, 7.0),
        (-1.9, 0.75, 9.0),
        (-2.9, 1.25, 5.0),
        (-1.7, 1.15, 6.0),
        (-2.45, 0.55, 5.5),
        (-2.05, 1.6, 4.5),
      ];
      final fade = (1 - t / 0.8).clamp(0.0, 1.0);
      for (var i = 0; i < drops.length; i++) {
        final (ang, speed, rad) = drops[i];
        final d = r * (1.08 + 0.25 * speed * Curves.easeOut.transform(t));
        final p = o + Offset(cos(ang + 0.15 * i), sin(ang + 0.15 * i)).scale(1, -1) * d;
        canvas.drawCircle(
            p, rad * (0.6 + 0.4 * fade), Paint()..color = target.withOpacity(fade));
      }
    }

    // Onde corail au départ.
    if (t < 0.5) {
      final k = t / 0.5;
      canvas.drawCircle(
        o,
        22 + 60 * Curves.easeOut.transform(k),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = kEcoCoral.withOpacity(0.7 * (1 - k)),
      );
    }
  }

  @override
  bool shouldRepaint(_RevealPainter old) => old.t != t || old.image != image;
}
