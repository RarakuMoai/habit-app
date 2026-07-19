import 'package:flutter/material.dart';

import '../utils/app_style.dart';

/// 長內容面板的純視覺捲動引導。
///
/// 底緣漸層與小箭頭讓內容看起來仍在往下延伸；捲到底後自然淡出。
/// 不顯示文字教學，也不放常駐捲軸，適合「設定內容＋固定底部按鈕」。
class ScrollContinuationArea extends StatefulWidget {
  final Widget child;
  final Color surfaceColor;
  final EdgeInsetsGeometry padding;

  const ScrollContinuationArea({
    super.key,
    required this.child,
    this.surfaceColor = Colors.white,
    this.padding = const EdgeInsets.only(bottom: 28),
  });

  @override
  State<ScrollContinuationArea> createState() => _ScrollContinuationAreaState();
}

class _ScrollContinuationAreaState extends State<ScrollContinuationArea> {
  // 每次開設定面板都從頂部開始，不讓 PageStorage 把前一個
  // 面板的捲動位置帶到下一個。
  final ScrollController _controller = ScrollController(
    keepScrollOffset: false,
  );
  bool _canScroll = false;
  bool _atBottom = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncScrollState);
    _syncAfterLayout();
  }

  @override
  void didUpdateWidget(covariant ScrollContinuationArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAfterLayout();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_syncScrollState)
      ..dispose();
    super.dispose();
  }

  void _syncAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncScrollState();
    });
  }

  void _syncScrollState() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final canScroll = position.maxScrollExtent > 1;
    final atBottom =
        !canScroll || position.pixels >= position.maxScrollExtent - 1;
    if (_canScroll == canScroll && _atBottom == atBottom) return;
    setState(() {
      _canScroll = canScroll;
      _atBottom = atBottom;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showContinuation = _canScroll && !_atBottom;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _syncAfterLayout();
        return false;
      },
      child: Stack(
        children: [
          SingleChildScrollView(
            key: const ValueKey('scroll-continuation-view'),
            controller: _controller,
            padding: widget.padding,
            child: widget.child,
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 48,
            child: IgnorePointer(
              child: AnimatedOpacity(
                key: const ValueKey('scroll-continuation-cue'),
                opacity: showContinuation ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        widget.surfaceColor.withValues(alpha: 0),
                        widget.surfaceColor.withValues(alpha: 0.94),
                      ],
                      stops: const [0, 0.78],
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: 30,
                      height: 20,
                      decoration: BoxDecoration(
                        color: widget.surfaceColor.withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(99),
                        border: AppCardStyle.hairline,
                        boxShadow: AppShadows.flat,
                      ),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: AppInk.iconFaint,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
