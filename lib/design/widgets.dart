import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// The Klaro mark.
///
/// Built on the exact typographic proportions of a bold geometric lowercase
/// `k.`: a tall vertical folio-spine ascender on the left, an x-height open
/// chevron separated by a crisp 10-unit synaptic clarity channel (eliminating
/// visual crowding at small sizes), flat horizontal typographic terminals on
/// the x-height and baseline, and the brand's full stop resting on the same
/// baseline. Strictly flat duotone (`tileColor` and `glyphColor`), zero
/// gradients.
class KlaroMark extends StatelessWidget {
  const KlaroMark({
    super.key,
    this.size = 28,
    this.primary,
    this.secondary,
    this.tile = true,
  });

  final double size;
  final Color? primary;
  final Color? secondary;
  final bool tile;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tileColor = primary ?? c.ink;
    final glyphColor = secondary ?? c.surface;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MarkPainter(
          tileColor: tileColor,
          glyphColor: glyphColor,
          tile: tile,
        ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter({
    required this.tileColor,
    required this.glyphColor,
    required this.tile,
  });

  final Color tileColor;
  final Color glyphColor;
  final bool tile;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    if (tile) {
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, s, s),
        Radius.circular(s * 0.2266),
      );
      canvas.drawRRect(r, Paint()..color = tileColor);
    }

    final fg = tile ? glyphColor : tileColor;
    final scale = (tile ? 1.0 : 1.12) * (s / 256.0);
    final ox = (s - 256.0 * scale) * 0.5;
    final oy = (s - 256.0 * scale) * 0.5;
    Offset pt(double x, double y) => Offset(ox + x * scale, oy + y * scale);

    final ink = Paint()
      ..color = fg
      ..style = PaintingStyle.fill;

    // 1. Ascender stem (folio spine): x = 46..79, y = 54..200
    final stem = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        pt(46, 54).dx,
        pt(46, 54).dy,
        pt(79, 200).dx,
        pt(79, 200).dy,
      ),
      Radius.circular(4.5 * scale),
    );
    canvas.drawRRect(stem, ink);

    // 2. Lowercase 'k' chevron in the x-height zone (y = 91..200), separated
    // from the stem by a 10-unit synaptic clarity channel (x = 79..89).
    final chevron = Path()
      ..moveTo(pt(89, 132).dx, pt(89, 132).dy)
      ..lineTo(pt(118, 91).dx, pt(118, 91).dy)
      ..lineTo(pt(156, 91).dx, pt(156, 91).dy)
      ..lineTo(pt(120, 135).dx, pt(120, 135).dy)
      ..lineTo(pt(158, 200).dx, pt(158, 200).dy)
      ..lineTo(pt(119, 200).dx, pt(119, 200).dy)
      ..lineTo(pt(89, 152).dx, pt(89, 152).dy)
      ..close();
    canvas.drawPath(chevron, ink);

    // 3. Full stop / focus node on the baseline (bottom at y = 200.5).
    canvas.drawCircle(pt(194, 182), 18.5 * scale, ink);
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.tileColor != tileColor ||
      old.glyphColor != glyphColor ||
      old.tile != tile;
}

class KlaroWordmark extends StatelessWidget {
  const KlaroWordmark({super.key, this.size = 28, this.showTagline = false});
  final double size;
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KlaroMark(size: size, tile: true, primary: c.ink, secondary: c.surface),
        SizedBox(width: size * 0.36),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'klaro.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: size * 0.68,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                height: 1.0,
                color: c.ink,
              ),
            ),
            if (showTagline)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  'Learning, remembered.',
                  style: MType.small.copyWith(color: c.inkFaint, fontSize: 11),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class MCard extends StatefulWidget {
  const MCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(MSpace.x5),
    this.onTap,
    this.color,
    this.border = true,
    this.radius = MRadius.lg,
    this.clip = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final bool border;
  final double radius;
  final bool clip;

  @override
  State<MCard> createState() => _MCardState();
}

class _MCardState extends State<MCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final interactive = widget.onTap != null;
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOutCubic,
      transform: Matrix4.translationValues(
        0,
        interactive && _hover ? -2.0 : 0.0,
        0,
      ),
      padding: widget.padding,
      decoration: BoxDecoration(
        color: widget.color ?? c.surface,
        borderRadius: BorderRadius.circular(widget.radius),
        border: widget.border
            ? Border.all(
                color: interactive && _hover
                    ? c.lineStrong
                    : c.line.withValues(alpha: 0.65),
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: context.elevationShadow(
              interactive && _hover ? 0.09 : 0.05,
              darkAlpha: interactive && _hover ? 0.40 : 0.28,
            ),
            blurRadius: interactive && _hover ? 30 : 22,
            offset: Offset(0, interactive && _hover ? 12 : 7),
          ),
        ],
      ),
      child: widget.clip
          ? ClipRRect(
              borderRadius: BorderRadius.circular(widget.radius),
              child: widget.child,
            )
          : widget.child,
    );
    if (!interactive) return content;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(widget.radius),
        clipBehavior: widget.clip ? Clip.antiAlias : Clip.none,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(widget.radius),
          hoverColor: Colors.transparent,
          child: content,
        ),
      ),
    );
  }
}

class MSectionHeader extends StatelessWidget {
  const MSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.padding = const EdgeInsets.only(bottom: MSpace.x3),
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: MType.h2.copyWith(color: c.ink)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: MType.small.copyWith(color: c.inkMuted),
                    ),
                  ),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

enum MButtonKind { primary, secondary, ghost, danger }

class MButton extends StatefulWidget {
  const MButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.kind = MButtonKind.secondary,
    this.dense = false,
    this.expand = false,
    this.trailing,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final MButtonKind kind;
  final bool dense;
  final bool expand;
  final Widget? trailing;

  @override
  State<MButton> createState() => _MButtonState();
}

class _MButtonState extends State<MButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final isDark = context.isDark;
    final kind = widget.kind;
    final disabled = widget.onPressed == null;
    final dense = widget.dense;

    final Color fg = switch (kind) {
      MButtonKind.primary => c.accentInk,
      MButtonKind.secondary => c.ink,
      MButtonKind.ghost => _hover ? c.ink : c.inkMuted,
      MButtonKind.danger => c.danger,
    };

    // Flat, zero-gradient surfaces. Light mode uses crisp opaque white / dark
    // pills; dark mode is its direct negative — a translucent frosted-glass
    // fill with a luminous specular border, never a top-to-bottom gradient.
    final Color fill = switch (kind) {
      MButtonKind.primary =>
        isDark
            ? Colors.white.withValues(alpha: _hover ? 0.98 : 0.93)
            : (_hover ? const Color(0xFF232329) : c.accent),
      MButtonKind.secondary =>
        isDark
            ? Colors.white.withValues(alpha: _hover ? 0.12 : 0.075)
            : (_hover ? c.surfaceAlt : c.surface),
      MButtonKind.danger =>
        isDark
            ? c.danger.withValues(alpha: _hover ? 0.20 : 0.13)
            : (_hover
                  ? Color.alphaBlend(
                      c.danger.withValues(alpha: 0.06),
                      c.dangerSoft,
                    )
                  : c.dangerSoft),
      MButtonKind.ghost =>
        _hover
            ? (isDark ? Colors.white.withValues(alpha: 0.07) : c.surfaceSunken)
            : Colors.transparent,
    };

    final Color borderColor = switch (kind) {
      MButtonKind.primary =>
        isDark
            ? Colors.white.withValues(alpha: 0.95)
            : Colors.black.withValues(alpha: 0.12),
      MButtonKind.secondary =>
        isDark
            ? Colors.white.withValues(alpha: _hover ? 0.24 : 0.15)
            : (_hover ? c.lineStrong : c.line),
      MButtonKind.danger => c.danger.withValues(
        alpha: isDark ? (_hover ? 0.44 : 0.30) : 0.22,
      ),
      MButtonKind.ghost =>
        isDark && _hover
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.transparent,
    };

    final shadows = (disabled || kind == MButtonKind.ghost)
        ? const <BoxShadow>[]
        : [
            BoxShadow(
              color: context.elevationShadow(
                _hover ? 0.10 : 0.05,
                darkAlpha: _hover ? 0.34 : 0.22,
              ),
              blurRadius: _hover ? 16 : 10,
              offset: Offset(0, _hover ? 5 : 2),
            ),
          ];

    final radius = BorderRadius.circular(dense ? 10 : 12);

    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: MouseRegion(
        cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() {
          _hover = false;
          _down = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: disabled ? null : (_) => setState(() => _down = true),
          onTapUp: disabled ? null : (_) => setState(() => _down = false),
          onTapCancel: disabled ? null : () => setState(() => _down = false),
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: _down ? 0.985 : 1,
            duration: const Duration(milliseconds: 90),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              height: dense ? 32 : 40,
              padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 16),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: radius,
                border: Border.all(color: borderColor),
                boxShadow: shadows,
              ),
              child: Row(
                mainAxisSize: widget.expand
                    ? MainAxisSize.max
                    : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    Icon(
                      widget.icon,
                      size: dense ? 15 : 17,
                      color: disabled ? c.inkFaint : fg,
                    ),
                    const SizedBox(width: 7),
                  ],
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MType.bodyStrong.copyWith(
                        fontSize: dense ? 12.5 : 13.5,
                        color: disabled ? c.inkFaint : fg,
                      ),
                    ),
                  ),
                  if (widget.trailing != null) ...[
                    const SizedBox(width: 8),
                    widget.trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MIconButton extends StatelessWidget {
  const MIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 36,
    this.selected = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return _IconHoverButton(
      icon: icon,
      onPressed: onPressed,
      tooltip: tooltip,
      size: size,
      selected: selected,
    );
  }
}

/// Layered icon button: the same raised surface, hairline and soft shadow as
/// [MButton], so icon controls never look flat next to it.
class _IconHoverButton extends StatefulWidget {
  const _IconHoverButton({
    required this.icon,
    required this.onPressed,
    required this.size,
    required this.selected,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final bool selected;

  @override
  State<_IconHoverButton> createState() => _IconHoverButtonState();
}

class _IconHoverButtonState extends State<_IconHoverButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final isDark = context.isDark;
    final disabled = widget.onPressed == null;
    final radius = BorderRadius.circular(10);
    final Color hoverFill = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : c.surface;
    final Color hoverBorder = isDark
        ? Colors.white.withValues(alpha: 0.16)
        : c.line;
    final button = Opacity(
      opacity: disabled ? 0.5 : 1,
      child: MouseRegion(
        cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: widget.selected
                  ? c.ink
                  : (_hover ? hoverFill : Colors.transparent),
              borderRadius: radius,
              border: Border.all(
                color: widget.selected
                    ? c.ink
                    : (_hover ? hoverBorder : Colors.transparent),
              ),
              boxShadow: _hover && !widget.selected
                  ? [
                      BoxShadow(
                        color: context.elevationShadow(0.08, darkAlpha: 0.24),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : const [],
            ),
            child: Icon(
              widget.icon,
              size: widget.size * 0.5,
              color: widget.selected
                  ? c.accentInk
                  : (_hover ? c.ink : c.inkMuted),
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip == null) return button;
    return Tooltip(message: widget.tooltip!, child: button);
  }
}

/// A segmented control with one sliding indicator, so switching a tab reads as
/// a single smooth movement instead of two independent colour flashes.
///
/// Used wherever a small set of mutually exclusive views exists (course panel,
/// filters, settings).
/// Fades its child in once, without keeping the previous child on screen.
///
/// Use it with a `ValueKey` that changes when the content changes: the old
/// widget is removed immediately and only the new one fades in, so there is no
/// ghosting, no double exposure and no layout jump between two stacked pages.
class MFadeIn extends StatelessWidget {
  const MFadeIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 180),
    this.offset = 0,
  });

  final Widget child;
  final Duration duration;

  /// Optional vertical drift in logical pixels while fading in.
  final double offset;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        final faded = Opacity(opacity: t, child: child);
        if (offset == 0) return faded;
        return Transform.translate(
          offset: Offset(0, (1 - t) * offset),
          child: faded,
        );
      },
      child: child,
    );
  }
}

class MSegmented extends StatelessWidget {
  const MSegmented({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
    this.dense = false,
  });

  final List<(String, IconData?)> items;
  final int index;
  final ValueChanged<int> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final height = dense ? 30.0 : 36.0;
    final count = items.isEmpty ? 1 : items.length;
    final active = index.clamp(0, count - 1);

    return LayoutBuilder(
      builder: (context, cons) {
        const pad = 3.0;
        final width = cons.maxWidth.isFinite ? cons.maxWidth : 0.0;
        final segWidth = ((width - pad * 2) / count).clamp(
          0.0,
          double.infinity,
        );

        return Container(
          height: height,
          padding: const EdgeInsets.all(pad),
          decoration: BoxDecoration(
            color: context.isDark
                ? Colors.white.withValues(alpha: 0.04)
                : c.surfaceAlt,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: context.isDark
                  ? Colors.white.withValues(alpha: 0.11)
                  : c.line,
            ),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                left: active * segWidth,
                top: 0,
                bottom: 0,
                width: segWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: context.isDark
                        ? Colors.white.withValues(alpha: 0.11)
                        : c.surface,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: context.isDark
                          ? Colors.white.withValues(alpha: 0.20)
                          : c.lineStrong.withValues(alpha: 0.7),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: context.elevationShadow(0.10, darkAlpha: 0.26),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < count; i++)
                    Expanded(
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onChanged(i),
                          child: Center(
                            child: TweenAnimationBuilder<double>(
                              duration: const Duration(milliseconds: 180),
                              tween: Tween(begin: 0, end: i == active ? 1 : 0),
                              builder: (context, t, _) {
                                final color = Color.lerp(c.inkMuted, c.ink, t)!;
                                final iconColor = Color.lerp(
                                  c.inkFaint,
                                  c.ink,
                                  t,
                                )!;
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (items[i].$2 != null) ...[
                                      Icon(
                                        items[i].$2,
                                        size: dense ? 13 : 14,
                                        color: iconColor,
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    Flexible(
                                      child: Text(
                                        items[i].$1,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: MType.small.copyWith(
                                          fontSize: dense ? 11 : 11.5,
                                          fontWeight: t > 0.5
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                          color: color,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class MChip extends StatelessWidget {
  const MChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
    this.tone = MChipTone.neutral,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final MChipTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final isDark = context.isDark;
    final (bg, fg, border) = switch (tone) {
      MChipTone.neutral => (
        selected
            ? c.ink
            : (isDark ? Colors.white.withValues(alpha: 0.065) : c.surface),
        selected ? c.surface : c.inkMuted,
        selected
            ? c.ink
            : (isDark ? Colors.white.withValues(alpha: 0.14) : c.line),
      ),
      MChipTone.accent => (
        selected
            ? c.accent
            : (isDark ? Colors.white.withValues(alpha: 0.09) : c.accentSoft),
        selected ? c.accentInk : c.accent,
        selected
            ? c.accent
            : (isDark
                  ? Colors.white.withValues(alpha: 0.16)
                  : Colors.transparent),
      ),
      MChipTone.amber => (
        isDark ? c.amber.withValues(alpha: 0.14) : c.amberSoft,
        c.amber,
        isDark ? c.amber.withValues(alpha: 0.28) : Colors.transparent,
      ),
      MChipTone.danger => (
        isDark ? c.danger.withValues(alpha: 0.14) : c.dangerSoft,
        c.danger,
        isDark ? c.danger.withValues(alpha: 0.28) : Colors.transparent,
      ),
    };
    // Animated rather than a hard colour swap: selecting a chip glides between
    // states instead of flashing.
    return MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(MRadius.pill),
            border: Border.all(color: border),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: context.elevationShadow(0.10, darkAlpha: 0.32),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : const [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: fg),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 180),
                  style: MType.small.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum MChipTone { neutral, accent, amber, danger }

class MEmpty extends StatelessWidget {
  const MEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.compact = false,
    this.framed = true,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final bool compact;
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (!framed) {
      final body = ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(MSpace.x6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: c.surfaceSunken,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 24, color: c.ink),
              ),
              const SizedBox(height: MSpace.x4),
              Text(
                title,
                textAlign: TextAlign.center,
                style: MType.h3.copyWith(color: c.ink, fontSize: 16.5),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: MType.small.copyWith(color: c.inkMuted, height: 1.5),
              ),
              if (action != null) ...[
                const SizedBox(height: MSpace.x5),
                action!,
              ],
            ],
          ),
        ),
      );
      // Scroll instead of letting Center clip the copy when the pane is short.
      return LayoutBuilder(
        builder: (context, cons) {
          final minH = cons.hasBoundedHeight ? cons.maxHeight : 0.0;
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minH),
              child: Center(child: body),
            ),
          );
        },
      );
    }
    final info = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: c.surfaceSunken,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, size: 22, color: c.ink),
        ),
        const SizedBox(width: MSpace.x5),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: MType.h3.copyWith(color: c.ink, fontSize: 16)),
              const SizedBox(height: 4),
              Text(
                message,
                style: MType.small.copyWith(color: c.inkMuted, height: 1.45),
              ),
            ],
          ),
        ),
      ],
    );
    return MCard(
      padding: EdgeInsets.symmetric(
        horizontal: MSpace.x6,
        vertical: compact ? MSpace.x5 : MSpace.x6,
      ),
      radius: MRadius.xl,
      child: LayoutBuilder(
        builder: (context, cons) {
          if (action == null) return info;
          // Narrow cards put the action under the text instead of squeezing it.
          if (cons.maxWidth < 420) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                info,
                const SizedBox(height: MSpace.x4),
                action!,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: info),
              const SizedBox(width: MSpace.x5),
              action!,
            ],
          );
        },
      ),
    );
  }
}

class MProgress extends StatelessWidget {
  const MProgress({
    super.key,
    required this.value,
    this.height = 6,
    this.color,
    this.track,
  });

  final double value;
  final double height;
  final Color? color;
  final Color? track;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: height,
        backgroundColor: track ?? c.surfaceSunken,
        valueColor: AlwaysStoppedAnimation(color ?? c.accent),
      ),
    );
  }
}

class MStat extends StatelessWidget {
  const MStat({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.icon,
  });

  final String label;
  final String value;
  final String? hint;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: c.inkFaint),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MType.label.copyWith(color: c.inkFaint, fontSize: 10.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: MType.h1.copyWith(fontSize: 26, color: c.ink, height: 1.0),
        ),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(
            hint!,
            style: MType.small.copyWith(color: c.inkMuted, fontSize: 11.5),
          ),
        ],
      ],
    );
  }
}

class MDivider extends StatelessWidget {
  const MDivider({super.key, this.vertical = false, this.inset = 0});
  final bool vertical;
  final double inset;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return vertical
        ? Container(
            width: 1,
            margin: EdgeInsets.symmetric(vertical: inset),
            color: c.line,
          )
        : Container(
            height: 1,
            margin: EdgeInsets.symmetric(horizontal: inset),
            color: c.line,
          );
  }
}

Future<T?> showMSheet<T>(
  BuildContext context, {
  required Widget child,
  double maxWidth = 520,
}) {
  final c = context.c;
  return showDialog<T>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (ctx) => Dialog(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MRadius.xl),
        side: BorderSide(color: c.line),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: 720),
        child: child,
      ),
    ),
  );
}

class MDialogHeader extends StatelessWidget {
  const MDialogHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onClose,
  });
  final String title;
  final String? subtitle;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MSpace.x6,
        MSpace.x5,
        MSpace.x4,
        MSpace.x4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: MType.h2.copyWith(color: c.ink)),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: MType.small.copyWith(color: c.inkMuted),
                  ),
                ],
              ],
            ),
          ),
          MIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Close',
            onPressed: onClose ?? () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
  if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
  return '${s}s';
}

String formatClock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

String relativeDate(DateTime d) {
  final now = DateTime.now();
  final diff = now.difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${d.day} ${_months[d.month - 1]}';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

double clamp01(double v) => math.min(1, math.max(0, v));
