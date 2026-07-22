import 'package:flutter/material.dart';

/// 足跡幣獎勵演出的共用錨點。
///
/// 兔咪頁面都留在 [IndexedStack] 裡，因此同一時間會存在多組兔咪與 AppBar。
/// 查詢時只取沒有被 [Offstage] 隱藏的那一組，讓獎勵在任何分頁都能從畫面上
/// 實際看見的兔咪飛向實際看見的足跡幣。
enum RewardAnimationAnchorKind { mascot, coinBalance }

abstract final class RewardAnimationAnchors {
  static final Map<RewardAnimationAnchorKind, Set<_RewardAnimationAnchorState>>
  _anchors = {};

  static void _register(_RewardAnimationAnchorState anchor) {
    (_anchors[anchor.widget.kind] ??= {}).add(anchor);
  }

  static void _unregister(_RewardAnimationAnchorState anchor) {
    _anchors[anchor.widget.kind]?.remove(anchor);
  }

  /// 回傳錨點的全域座標；尚未 layout 或目前在其他分頁時回傳 null。
  static Offset? globalPoint(RewardAnimationAnchorKind kind) {
    final candidates = _anchors[kind]?.toList(growable: false).reversed;
    if (candidates == null) return null;
    for (final candidate in candidates) {
      final point = candidate._globalPointIfOnstage();
      if (point != null) return point;
    }
    return null;
  }
}

class RewardAnimationAnchor extends StatefulWidget {
  const RewardAnimationAnchor({
    super.key,
    required this.kind,
    required this.child,
    this.alignment = Alignment.center,
  });

  final RewardAnimationAnchorKind kind;
  final Alignment alignment;
  final Widget child;

  @override
  State<RewardAnimationAnchor> createState() => _RewardAnimationAnchorState();
}

class _RewardAnimationAnchorState extends State<RewardAnimationAnchor> {
  final GlobalKey _renderKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    RewardAnimationAnchors._register(this);
  }

  @override
  void didUpdateWidget(covariant RewardAnimationAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind == widget.kind) return;
    RewardAnimationAnchors._anchors[oldWidget.kind]?.remove(this);
    RewardAnimationAnchors._register(this);
  }

  @override
  void dispose() {
    RewardAnimationAnchors._unregister(this);
    super.dispose();
  }

  Offset? _globalPointIfOnstage() {
    if (!mounted) return null;
    var onstage = true;
    context.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is Offstage && widget.offstage) {
        onstage = false;
        return false;
      }
      return true;
    });
    if (!onstage) return null;

    final renderObject = _renderKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return null;
    }
    return renderObject.localToGlobal(
      widget.alignment.alongSize(renderObject.size),
    );
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _renderKey, child: widget.child);
  }
}
