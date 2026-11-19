import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Smooth, inertia-interpolated scroll view for desktop mouse wheel and trackpad.
/// Eliminates the choppy stepped jumping of standard Windows wheel events.
class MSmoothScrollView extends StatefulWidget {
  const MSmoothScrollView({
    super.key,
    required this.child,
    this.padding,
    this.controller,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller;

  @override
  State<MSmoothScrollView> createState() => _MSmoothScrollViewState();
}

class _MSmoothScrollViewState extends State<MSmoothScrollView>
    with SingleTickerProviderStateMixin {
  // Scroll extents can be inverted (and briefly negative) while a page grows
  // or shrinks during a window resize; clamp() throws when min > max.
  double _lo(ScrollPosition p) => math.min(p.minScrollExtent, p.maxScrollExtent);
  double _hi(ScrollPosition p) => math.max(p.minScrollExtent, p.maxScrollExtent);

  late final ScrollController _ctrl;
  late final bool _ownsController;
  late final Ticker _ticker;
  double _target = 0;
  bool _animating = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _ctrl = widget.controller ?? ScrollController();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    if (_ownsController) {
      _ctrl.dispose();
    }
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_ctrl.hasClients) {
      _stopTicker();
      return;
    }
    final pos = _ctrl.position;
    _target = _target.clamp(_lo(pos), _hi(pos));
    final current = _ctrl.offset;
    final diff = _target - current;
    if (diff.abs() < 0.6) {
      if (diff.abs() > 0.01) {
        _ctrl.jumpTo(_target);
      }
      _stopTicker();
      return;
    }
    // Exponential smoothing factor (~60-120Hz frame-independent feel)
    final step = diff * 0.22;
    _ctrl.jumpTo(
      (current + step).clamp(_lo(pos), _hi(pos)),
    );
  }

  void _stopTicker() {
    if (_animating) {
      _animating = false;
      _ticker.stop();
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent && _ctrl.hasClients) {
      final pos = _ctrl.position;
      if (!_animating) {
        _target = _ctrl.offset;
      }
      _target = (_target + event.scrollDelta.dy * 1.15)
          .clamp(_lo(pos), _hi(pos));
      if (!_animating) {
        _animating = true;
        _ticker.start();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          scrollbars: true,
          physics: const NeverScrollableScrollPhysics(),
          dragDevices: {
            ui.PointerDeviceKind.touch,
            ui.PointerDeviceKind.mouse,
            ui.PointerDeviceKind.trackpad,
            ui.PointerDeviceKind.stylus,
          },
        ),
        child: SingleChildScrollView(
          controller: _ctrl,
          padding: widget.padding,
          child: widget.child,
        ),
      ),
    );
  }
}
