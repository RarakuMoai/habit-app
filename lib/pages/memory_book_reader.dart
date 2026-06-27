import 'package:flutter/material.dart';

import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/story_catalog.dart';
import '../utils/story_store.dart';

/// 全螢幕「回憶本」繪本閱讀器：橫向翻頁，一個事件一頁（單圖繪本）。
/// 翻到的那頁會標記為已讀（清掉未讀，未來控制「書發亮」熄滅）。
class MemoryBookReader extends StatefulWidget {
  /// 已解鎖事件，依解鎖時間排序（舊→新）。
  final List<StoryUnlock> entries;
  final int initialIndex;

  const MemoryBookReader({
    super.key,
    required this.entries,
    this.initialIndex = 0,
  });

  @override
  State<MemoryBookReader> createState() => _MemoryBookReaderState();
}

class _MemoryBookReaderState extends State<MemoryBookReader> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.entries.length - 1);
    _controller = PageController(initialPage: _index);
    _markRead(_index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _markRead(int i) {
    if (i < 0 || i >= widget.entries.length) return;
    StoryStore.markRead(widget.entries[i].id);
  }

  void _onPageChanged(int i) {
    playHaptic(HapticLevel.selection);
    setState(() => _index = i);
    _markRead(i);
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    return Scaffold(
      backgroundColor: const Color(0xFFFBF3E8), // 暖書頁底
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: entries.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (_, i) => _MemorySpread(
                event: storyEventById(entries[i].id),
                date: entries[i].date,
              ),
            ),
            Positioned(
              top: 6,
              right: 8,
              child: _CircleButton(
                icon: Icons.close_rounded,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            if (entries.length > 1)
              Positioned(
                bottom: 14,
                left: 0,
                right: 0,
                child: _PageDots(count: entries.length, index: _index),
              ),
          ],
        ),
      ),
    );
  }
}

class _MemorySpread extends StatelessWidget {
  final StoryEventSpec event;
  final DateTime date;

  const _MemorySpread({required this.event, required this.date});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 34),
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: kMemoryAccent.withValues(alpha: 0.18),
                ),
                boxShadow: AppShadows.card,
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                event.image,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _ImageFallback(),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            event.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppInk.strong,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            _formatDate(date),
            style: TextStyle(
              color: kMemoryAccent.withValues(alpha: 0.9),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 14),
          for (final line in event.captions)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                line,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppInk.soft,
                  fontSize: 14.5,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// 繪本圖缺檔時的柔和 fallback（出貨會放真的圖，平常看不到）。
class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            kMemoryAccent.withValues(alpha: 0.18),
            const Color(0xFFFFF6EC),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.auto_stories_rounded,
          size: 64,
          color: kMemoryAccent.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.86),
      shape: const CircleBorder(),
      elevation: 1.5,
      shadowColor: Colors.black26,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 22, color: AppInk.soft),
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  final int count;
  final int index;

  const _PageDots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 18 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i == index
                  ? kMemoryAccent
                  : kMemoryAccent.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}

String _formatDate(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year} / $m / $day';
}
