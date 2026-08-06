// 動效預覽台（開發用，不進正式流程）。
//
// 起因：解鎖演出第一版只有測試驗證就交出去，實機看才發現搖晃根本讀不到、
// 標籤重疊很醜。要「改到滿意為止」就得能**穩定地、重複地**看到同一段動畫——
// 而在真實頁面裡要先進衣櫃、捲到曲庫、點解鎖、過確認框，每次位置還會變，
// 抽格時得靠猜時間點，前一輪就因此連續三次裁錯區域。
//
// 這裡把要看的動效單獨放在乾淨背景上**自動循環**，並在畫面上打出
// 「距離這一輪開始幾毫秒」。抽格之後不必再猜：每一格自己會說它是第幾拍。
//
// 啟動方式（`kDevToolsEnabled` 閘門，正式版永遠進不來）：
//   flutter run --dart-define=MOTION_PREVIEW=1
//   flutter build ios --simulator --debug --dart-define=MOTION_PREVIEW=1
//
// 加新動效時在 [_demos] 補一格就好，不要為了看一個動畫去改真實頁面。

import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/feature_flags.dart';
import '../widgets/unlock_morph_button.dart';

/// 是否由 `--dart-define=MOTION_PREVIEW=1` 直接啟動預覽台。
///
/// ⚠️ 走 `String.fromEnvironment` 而不是 `bool.fromEnvironment`：後者只認
/// `true`／`false`，傳 `=1` 會靜靜地變成 false（踩過一次）。這裡與 `SCENE_PERF`
/// 一樣同時接受 `1` 與 `true`。
const String _kMotionPreviewRaw = String.fromEnvironment('MOTION_PREVIEW');
const bool kMotionPreviewRequested =
    (_kMotionPreviewRaw == '1' || _kMotionPreviewRaw == 'true') &&
    kDevToolsEnabled;

/// 一輪演出之間的間隔：留白讓錄影能清楚看見「起點」在哪。
const Duration _kGap = Duration(milliseconds: 1200);

class MotionPreviewPage extends StatefulWidget {
  const MotionPreviewPage({super.key});

  @override
  State<MotionPreviewPage> createState() => _MotionPreviewPageState();
}

class _MotionPreviewPageState extends State<MotionPreviewPage>
    with SingleTickerProviderStateMixin {
  /// 時間戳專用的控制器。
  ///
  /// ⚠️ **不要用 Timer ＋ DateTime.now() 算這個數字。** 第一版那樣做，debug build
  /// 在模擬器上掉幀，setState 驅動的文字比動畫落後好幾百毫秒——畫面標「304ms
  /// 搖晃」時鎖其實已經彈開了，抽格分析整個被誤導。時間戳必須跟動畫走**同一條
  /// frame pipeline**，才會標在同一幀上。
  late final AnimationController _stamp;

  /// 目前這一輪的「已擁有」狀態；false→true 就會觸發解鎖演出。
  bool _owned = false;

  Timer? _loop;

  @override
  void initState() {
    super.initState();
    _stamp = AnimationController(vsync: this, duration: kUnlockTotal);
    _schedule();
  }

  void _schedule() {
    _loop?.cancel();
    setState(() => _owned = false);
    // 下一幀才翻面，否則 didUpdateWidget 收不到「false→true」的變化。
    _loop = Timer(const Duration(milliseconds: 60), () {
      if (!mounted) return;
      setState(() => _owned = true);
      _stamp.forward(from: 0); // 與按鈕同時起跑，同一條 pipeline
      _loop = Timer(kUnlockTotal + _kGap, _schedule);
    });
  }

  @override
  void dispose() {
    _loop?.cancel();
    _stamp.dispose();
    super.dispose();
  }

  int get _elapsedMs => (_stamp.value * kUnlockTotal.inMilliseconds).round();

  /// 這一格落在哪一拍——抽格時最想知道的就是這個。
  String get _phase {
    if (!_owned) return 'idle';
    final ms = _elapsedMs;
    if (ms < 180) return '蓄力';
    if (ms < 900) return '搖晃';
    if (ms < 1300) return '彈開/餘韻';
    if (ms < 1720) return '化成加入';
    return '完成';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFDF9),
      appBar: AppBar(
        title: const Text('動效預覽（dev）'),
        backgroundColor: const Color(0xFFFFFDF9),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 時間戳：抽格時每一格自己會說它是第幾毫秒、第幾拍。
            AnimatedBuilder(
              animation: _stamp,
              builder: (_, _) => Text(
                '${_owned ? _elapsedMs.toString().padLeft(4, "0") : "----"} ms   $_phase',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  fontFeatures: [FontFeature.tabularFigures()],
                  color: Color(0xFF453229),
                ),
              ),
            ),
            const SizedBox(height: 28),
            // 原尺寸：這是使用者實際會看到的大小，調動效一律以它為準。
            _labelled('原尺寸（實際大小）', 1),
            const SizedBox(height: 24),
            // 放大版：同一個元件放大檢視細節，不改任何參數。
            _labelled('放大 3× （只為了看細節）', 3),
          ],
        ),
      ),
    );
  }

  Widget _labelled(String caption, double zoom) {
    return Column(
      children: [
        Text(
          caption,
          style: const TextStyle(fontSize: 12, color: Color(0xFF8C7A6E)),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 44.0 * zoom,
          child: Transform.scale(
            scale: zoom,
            child: Center(
              child: SizedBox(
                width: 140,
                child: UnlockMorphButton(
                  owned: _owned,
                  lockedLabel: '解鎖 50',
                  unlockedLabel: '加入',
                  unlockedIcon: Icons.playlist_add_rounded,
                  color: const Color(0xFF4A6FA5),
                  onLockedTap: () {},
                  onUnlockedTap: () {},
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
