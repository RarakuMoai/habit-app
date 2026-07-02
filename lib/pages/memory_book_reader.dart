import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/story_catalog.dart';
import '../utils/story_store.dart';

/// 閱讀器的一個跨頁：某個已解鎖事件的第 [pageNo] 頁。
class _SpreadEntry {
  final StoryEventSpec event;
  final StoryPage page;
  final int pageNo; // 1-based
  final DateTime date;
  const _SpreadEntry(this.event, this.page, this.pageNo, this.date);
}

/// 全螢幕「回憶本」繪本閱讀器：橫向翻頁，一個事件一或多頁（每頁單圖）。
/// 翻到的那頁會標記為已讀（清掉未讀，未來控制「書發亮」熄滅）。
class MemoryBookReader extends StatefulWidget {
  /// 已解鎖事件，依解鎖時間排序（舊→新）。
  final List<StoryUnlock> entries;

  /// 初始翻到第幾個「事件」（多頁事件會落在它的第一頁）。
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
  late final List<_SpreadEntry> _spreads;
  late int _index;

  @override
  void initState() {
    super.initState();
    // 事件攤平成跨頁（多頁事件依序展開，像同一本書的連續幾頁）。
    _spreads = [
      for (final u in widget.entries)
        for (final (pi, page) in storyEventById(u.id).pages.indexed)
          _SpreadEntry(storyEventById(u.id), page, pi + 1, u.date),
    ];
    final eventIndex = widget.initialIndex.clamp(0, widget.entries.length - 1);
    final targetId = widget.entries.isEmpty
        ? null
        : widget.entries[eventIndex].id;
    final start = _spreads.indexWhere((s) => s.event.id == targetId);
    _index = start < 0 ? 0 : start;
    _controller = PageController(initialPage: _index);
    _markRead(_index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _markRead(int i) {
    if (i < 0 || i >= _spreads.length) return;
    StoryStore.markRead(_spreads[i].event.id);
  }

  void _onPageChanged(int i) {
    playHaptic(HapticLevel.selection);
    setState(() => _index = i);
    _markRead(i);
  }

  @override
  Widget build(BuildContext context) {
    final entries = _spreads;
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
                // 換頁重掛，台詞才會重新逐句浮現
                key: ValueKey('${entries[i].event.id}_${entries[i].pageNo}'),
                entry: entries[i],
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
  final _SpreadEntry entry;

  const _MemorySpread({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final event = entry.event;
    final multiPage = event.pages.length > 1;
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
                entry.page.image,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _ImageFallback(),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            multiPage ? '${event.title}・${entry.pageNo}' : event.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppInk.strong,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            _formatDate(entry.date),
            style: TextStyle(
              color: kMemoryAccent.withValues(alpha: 0.9),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 14),
          _CaptionsFadeIn(lines: entry.page.captions),
        ],
      ),
    );
  }
}

/// 台詞逐句浮現（掛上畫面時每句依序淡入＋微上浮，錯開一小拍）。
/// 全部先佔位（透明），出現時版面不會往下跳。
class _CaptionsFadeIn extends StatefulWidget {
  final List<String> lines;

  const _CaptionsFadeIn({required this.lines});

  @override
  State<_CaptionsFadeIn> createState() => _CaptionsFadeInState();
}

class _CaptionsFadeInState extends State<_CaptionsFadeIn> {
  int _shown = 0;
  final List<Timer> _timers = [];

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < widget.lines.length; i++) {
      _timers.add(
        Timer(Duration(milliseconds: 240 + i * 420), () {
          if (mounted) setState(() => _shown = i + 1);
        }),
      );
    }
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (i, line) in widget.lines.indexed)
          AnimatedSlide(
            offset: i < _shown ? Offset.zero : const Offset(0, 0.25),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: i < _shown ? 1 : 0,
              duration: const Duration(milliseconds: 420),
              child: Padding(
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
            ),
          ),
      ],
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
