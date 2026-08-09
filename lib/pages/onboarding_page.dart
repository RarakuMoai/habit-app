import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/bgm_service.dart';
import '../utils/input_formatters.dart';
import '../utils/mascot.dart';
import '../utils/prefs_keys.dart';
import '../utils/sfx_service.dart';
import '../utils/weight_records.dart';
import '../widgets/audio_control_button.dart';
import '../widgets/avg_scene.dart';
import '../widgets/mascot_scene.dart';

// ⚠️ 暫時的：AVG 對話框兩版並存，讓使用者在實機挑一版。挑定後把這個常數與
// AvgLayout 裡沒被選中的那一版一起刪掉，不要留成永久設定。
const AvgLayout _kAvgLayout = AvgLayout.solidBox;

// 引導頁「習慣選擇」清單（喝水功能預設開啟，「喝足夠的水」在 _finish 直接加，故不列入）
// freq=true：適合「每週幾次」的習慣，選取後會出現每日/每週切換
//
// name 沒有走 l10n：這些名稱選取後會直接存成習慣名，而首頁的去重與
// 喝水／體重連動判定都比對它（見 kHomePresets）。翻譯會讓連動失效。
// 詳見 docs/i18n_migration.md 的跳過清單。
const List<({String emoji, String name, bool freq})> _kOnboardingHabits = [
  (emoji: '🦷', name: '刷牙', freq: false),
  (emoji: '🧹', name: '整理環境', freq: false),
  (emoji: '📖', name: '閱讀', freq: true),
  (emoji: '🌅', name: '早起', freq: false),
  (emoji: '🏃', name: '運動', freq: true),
  (emoji: '🥗', name: '飲食控制', freq: false),
  (emoji: '🧘', name: '冥想', freq: true),
  (emoji: '🌙', name: '早睡', freq: false),
];

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  AppLocalizations get _l10n => AppLocalizations.of(context);

  final PageController _pageController = PageController();
  int _currentPage = 0;

  // 畫面1：抵達（你搬進來那天敲門，兔咪慢半拍來開門）的 AVG 場景。
  // 台詞走 l10n：這幾句是世界觀的第一印象，不能只有中文（見 docs/world_setting.md）。
  // 四句的表情：門後應聲(wake) → 察覺是你 → 坦白自己也剛搬來 → 邀你進門(smile)。
  static const List<String> _kArrivalEmotions = [
    'wake',
    'neutral_front',
    'neutral_front',
    'smile',
  ];

  List<AvgLine> get _arrivalLines {
    final texts = _l10n.obArrivalLines.split('|');
    return [
      for (var i = 0; i < texts.length; i++)
        AvgLine(
          texts[i],
          emotion: i < _kArrivalEmotions.length
              ? _kArrivalEmotions[i]
              : 'neutral_front',
        ),
    ];
  }

  bool _page1Done = false;

  // 畫面2：吉祥物名稱
  final TextEditingController _mascotController = TextEditingController();
  // 預設名要走 l10n，但 field initializer 拿不到 context，延到
  // didChangeDependencies 填一次。
  bool _mascotDefaultApplied = false;
  // 骰子隨機名字用的小名池：文案在 ARB（各語言各自挑一組，不是逐字翻）。
  List<String> get _mascotNamePool => _l10n.mascotNamePool.split('|');
  final math.Random _nameRng = math.Random();

  // 畫面3：用戶暱稱
  final TextEditingController _nicknameController = TextEditingController();

  // 用戶暱稱（畫面3填完後存起來）
  String _nickname = '';

  // ── 頁面定義表：頁數、順序、返回鍵的子步驟邏輯都從這裡推導 ──
  // 新增/刪除頁面只要改這張表，進度點數量與換頁邊界會自動跟上。
  // inSubStep 回 true 時返回鍵先退出追問子步驟（exitSubStep）而不換頁。
  //
  // 五頁：抵達 → 你想怎麼叫牠 → 牠怎麼叫你 → 架子上放什麼 → 進門。
  // 2026-08-09 從九頁砍下來，移出的東西與理由：
  // - 喝水／專注／家庭三頁功能開關 → 預設開啟，設定裡可關。原本是連續三次
  //   同版型的 yes/no，且「不用了」是紅色按鈕＋二次確認，那是留存暗黑模式，
  //   跟「不責備、不催促、是邀請不是推銷」的角色設定直接對撞。
  // - 身體資訊頁（性別／身高／體重／目標體重／生日／活動量）→ 移到體重與
  //   喝水頁的「補上資料」卡，點了開 ProfileEditPage。原本兔咪會在 BMI 異常時
  //   換 sad 表情評論使用者的身體，違反「不評分」。
  late final List<
    ({
      Widget Function() build,
      bool Function() inSubStep,
      VoidCallback exitSubStep,
    })
  >
  _pages = [
    (build: _buildArrivalPage, inSubStep: _noSubStep, exitSubStep: _noopSubStep),
    (build: _buildNamePage, inSubStep: _noSubStep, exitSubStep: _noopSubStep),
    (
      build: _buildNicknamePage,
      inSubStep: _noSubStep,
      exitSubStep: _noopSubStep,
    ),
    (
      build: _buildHabitPickerPage,
      inSubStep: _noSubStep,
      exitSubStep: _noopSubStep,
    ),
    (build: _buildDonePage, inSubStep: _noSubStep, exitSubStep: _noopSubStep),
  ];

  static bool _noSubStep() => false;
  static void _noopSubStep() {}

  // 習慣選擇頁：使用者勾選的習慣名稱
  final Set<String> _selectedHabits = {};
  // 習慣選擇頁：設為「每週」的習慣 → 名稱對應每週次數；未列入者為每日
  final Map<String, int> _weeklyTimes = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 預設兔咪名走 l10n（英文介面是 Tumi）；只在還沒填過時帶入，
    // 不會蓋掉使用者已經打的字。
    if (!_mascotDefaultApplied) {
      _mascotDefaultApplied = true;
      _mascotController.text = _l10n.mascotDefaultName;
    }
  }

  @override
  void initState() {
    super.initState();
    _nicknameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _pageController.dispose();
    _mascotController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  void _nextPage({bool playSound = true}) {
    if (playSound) _playOnboardingSfx(SfxCue.tap);
    unawaited(_ensureOnboardingBgm());
    // 換頁前先收起鍵盤，避免下一頁殘留鍵盤
    FocusScope.of(context).unfocus();
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
      setState(() => _currentPage++);
    }
  }

  // 音效一律配對觸覺回饋；onboarding 的 tap 比預設再輕一階（selection），
  // 引導流程點擊密集，避免震過頭
  void _playOnboardingSfx(SfxCue cue) {
    playFeedback(cue, haptic: cue == SfxCue.tap ? HapticLevel.selection : null);
  }

  Future<void> _ensureOnboardingBgm({bool unmute = false}) async {
    try {
      await BgmService.instance.ensurePlaying(
        'sounds/bgm_onboarding.m4a',
        unmute: unmute,
      );
    } catch (e, st) {
      debugPrint('Onboarding BGM ensure failed: $e\n$st');
    }
  }

  // 回上一步：若該頁正處於追問子步驟，先退回初始選項；否則回上一畫面
  void _handleBack() {
    _playOnboardingSfx(SfxCue.cancel);
    // 換頁前先收起鍵盤，與 _nextPage 一致
    FocusScope.of(context).unfocus();
    final page = _pages[_currentPage];
    if (page.inSubStep()) {
      setState(page.exitSubStep);
      return;
    }
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
      setState(() => _currentPage--);
    }
  }

  // 儲存所有設定並完成 onboarding
  Future<void> _finish() async {
    _playOnboardingSfx(SfxCue.complete);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.onboardingDone, true);
    await prefs.setString(
      PrefsKeys.mascotName,
      _mascotController.text.trim().isEmpty
          ? _l10n.mascotDefaultName
          : _mascotController.text.trim(),
    );
    // 同步全域名字，帶 {name} 的系統文案立刻換掉
    MascotName.set(_mascotController.text);
    await prefs.setString(
      PrefsKeys.userNickname,
      _nicknameController.text.trim().isEmpty
          ? _l10n.hpNicknameFallback
          : _nicknameController.text.trim(),
    );
    // 功能一律預設開啟。原本這三個是引導頁裡三頁 yes/no 問卷，現在移除了——
    // 想關的人在設定 → 功能開關關掉，比在還沒用過時先問一輪誠實得多。
    await prefs.setBool(PrefsKeys.waterEnabled, true);
    await prefs.setBool(PrefsKeys.timerEnabled, true);
    await prefs.setBool(PrefsKeys.familyEnabled, true);
    await prefs.setBool(PrefsKeys.weightTrackingEnabled, true);

    // 身體資訊（性別／身高／體重／生日／活動量）不在引導頁問了，改由體重與
    // 喝水頁的「補上資料」卡帶到 ProfileEditPage。那些頁面本來就容許缺值。

    // 喝水功能預設開啟 → 「喝足夠的水」一起放進架子上
    _selectedHabits.add('喝足夠的水');
    // 引導頁「習慣選擇頁」勾選的習慣
    await _addPickedHabits(prefs);

    if (!mounted) return;
    // 切換 BGM 到主 app 曲目（cross-fade）
    unawaited(BgmService.instance.play('sounds/bgm_main.m4a'));
    unawaited(Navigator.of(context).pushReplacementNamed('/home'));
  }

  // 將習慣選擇頁勾選的習慣寫入習慣清單
  Future<void> _addPickedHabits(SharedPreferences prefs) async {
    if (_selectedHabits.isEmpty) return;
    final habitsJson = prefs.getString(PrefsKeys.habits);
    var habits = <Map<String, dynamic>>[];
    if (habitsJson != null) {
      final decoded = jsonDecode(habitsJson) as List<dynamic>;
      habits = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    for (final name in _selectedHabits) {
      if (habits.any((h) => h['name'] == name)) continue;
      final weeklyTimes = _weeklyTimes[name];
      if (weeklyTimes != null) {
        habits.add({
          'name': name,
          'done': false,
          'frequency': 'weekly',
          'weeklyTarget': weeklyTimes,
          'weeklyDates': <String>[],
        });
      } else {
        habits.add({'name': name, 'done': false});
      }
    }
    // 體重紀錄、喝足夠的水跟體重/喝水頁連動，預設固定排在最上面（視覺一致）；
    // 之後使用者仍可在首頁自由拖曳調整順序。逐個 insert 到最前，所以這裡先列
    // 水、再列體重，最終呈現順序是 [體重紀錄, 喝足夠的水, ...]。
    const pinnedTop = <String>['喝足夠的水', kWeightHabitName];
    for (var p = 0; p < pinnedTop.length; p++) {
      final i = habits.indexWhere((h) => h['name'] == pinnedTop[p]);
      if (i > 0) habits.insert(0, habits.removeAt(i));
    }
    await prefs.setString(PrefsKeys.habits, jsonEncode(habits));
  }

  // 通用對話氣泡樣式
  Widget _speechBubble(String text, {double fontSize = 16}) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.22)),
            boxShadow: [
              BoxShadow(
                color: Colors.orange.withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: fontSize,
              height: 1.38,
              color: Colors.orange.shade900,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        Positioned(
          top: -7,
          left: 0,
          right: 0,
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Center(
              child: Container(
                width: 15,
                height: 15,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.88),
                  border: Border(
                    left: BorderSide(
                      color: Colors.orange.withValues(alpha: 0.16),
                    ),
                    top: BorderSide(
                      color: Colors.orange.withValues(alpha: 0.16),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 吉祥物（依情境切換情緒）。走 MascotStage 讓引導頁的兔咪跟主 app
  // 一樣活著：呼吸、眨眼（neutral_front 有閉眼差分）、點擊彈跳＋星星。
  Widget _mascot({double size = 80, String emotion = 'neutral_front'}) {
    // 透過 MascotEmotion 取，會自動走新 CG / 舊圖路由
    final asset = MascotEmotion.values
        .firstWhere(
          (e) => e.assetKey == emotion,
          orElse: () => MascotEmotion.neutralFront,
        )
        .assetPath;
    return SizedBox(
      width: size,
      height: size,
      // MascotStage 內部是固定 252 的舞台，FittedBox 等比縮到引導頁要的大小
      child: FittedBox(
        child: MascotStage(
          asset: asset,
          accent: Colors.orange,
          reactionTick: 0,
          onTap: () => _playOnboardingSfx(SfxCue.tap),
        ),
      ),
    );
  }

  // ── 畫面1：吉祥物甦醒 ──
  // 引導頁版型：兔咪固定在上方，內容在下方區域置中（可捲動）。
  // 鍵盤彈出時，有掛 scrollController 的頁面會自動捲到底（didChangeMetrics
  // 觸發），讓底部按鈕浮到鍵盤上緣；兔咪/上半部欄位會被推出畫面上方，但
  // 使用者可往上滑回去。沒掛 controller 的頁面走預設行為（內容置中）。
  Widget _mascotPage({
    required String emotion,
    required Widget content,
    ScrollController? scrollController,
    // 緊湊版用：習慣選擇頁內容塞得下、不需要兔咪 200，給 140 + 縮 padding
    // 就能避開 scroll，整頁更俐落
    double mascotSize = 200,
    EdgeInsets contentPadding = const EdgeInsets.all(32),
    double mascotBottomSpacing = 16,
    // 點空白處的額外行為（第一頁用來快轉打字）
    VoidCallback? onTapBackground,
  }) {
    return GestureDetector(
      // 點空白處收起鍵盤
      onTap: () {
        FocusScope.of(context).unfocus();
        onTapBackground?.call();
      },
      behavior: HitTestBehavior.opaque,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            controller: scrollController,
            // Clamping：內容塞得下時完全不能滑（不像 iOS 預設 Bouncing 永遠
            // 能拉橡皮筋）；內容超出時還是能正常 scroll，只是邊界硬停。
            // 給引導頁俐落感，又保留 keyboard 自動捲到底的能力。
            physics: const ClampingScrollPhysics(),
            child: Padding(
              padding: contentPadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _mascot(size: mascotSize, emotion: emotion),
                  SizedBox(height: mascotBottomSpacing),
                  content,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 畫面1：抵達 ──
  // 你搬進來那天敲門，兔咪慢半拍來開門，屋子還很空。
  // 四句台詞的情緒：門後應聲(wake) → 察覺是你(neutral) → 坦白自己也剛搬來
  // → 邀你進門(smile)。
  Widget _buildArrivalPage() {
    return Stack(
      fit: StackFit.expand,
      children: [
        AvgScene(
          background: 'assets/scenes/onboarding/onboarding_bg_v3.png',
          lines: _arrivalLines,
          layout: _kAvgLayout,
          speakerName: _mascotController.text.trim().isEmpty
              ? _l10n.mascotDefaultName
              : _mascotController.text.trim(),
          tapHint: _l10n.obTapToContinue,
          onTapSound: () => _playOnboardingSfx(SfxCue.tap),
          onFinished: () => setState(() => _page1Done = true),
        ),
        // 全部講完才浮出「繼續」，壓在對話框上方。講到一半就出現會催促使用者。
        if (_page1Done)
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 152),
                child: ElevatedButton(
                  onPressed: _nextPage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 14,
                    ),
                  ),
                  child: Text(
                    _l10n.obContinue,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // 骰子：從名字池隨機抽一個（排除目前這個），填回輸入框。
  void _rollMascotName() {
    _playOnboardingSfx(SfxCue.tap);
    final current = _mascotController.text.trim();
    final pool = _mascotNamePool.where((n) => n != current).toList();
    if (pool.isEmpty) return;
    final pick = pool[_nameRng.nextInt(pool.length)];
    setState(() {
      _mascotController.text = pick;
      _mascotController.selection = TextSelection.collapsed(
        offset: pick.length,
      );
    });
  }

  Widget _diceButton() {
    return Material(
      color: Colors.orange,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _rollMascotName,
        child: const Padding(
          padding: EdgeInsets.all(15),
          child: Icon(Icons.casino_rounded, color: Colors.white, size: 24),
        ),
      ),
    );
  }

  // ── 畫面2：你想怎麼叫牠 ──
  // 牠本來就有名字（mascotDefaultName），你取的是「想怎麼叫牠」——所以這裡是
  // 全 app 唯一一次兔咪自稱名字（命名儀式，見 docs/world_setting.md）。
  Widget _buildNamePage() {
    return _mascotPage(
      emotion: 'smile',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _speechBubble(_l10n.obNameBubble(_l10n.mascotDefaultName)),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _mascotController,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18),
                  // 名字會被帶進很多系統文案（「{name}的夥伴檔案」…），限長
                  // 是為了防破版，所以數的是顯示寬度而非字元數：中文 6 字
                  // 與英文 12 字元同寬（見 kMascotNameMaxUnits）。
                  inputFormatters: const [
                    DisplayWidthLimitingFormatter(kMascotNameMaxUnits),
                  ],
                  decoration: InputDecoration(
                    hintText: _l10n.obNameHint,
                    counterText: '',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.orange.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Colors.orange),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _diceButton(),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _l10n.obNameDiceHint,
            style: const TextStyle(fontSize: 13, color: AppInk.faint),
          ),
          const SizedBox(height: 26),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _nextPage,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                _l10n.obNext,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 畫面3：牠怎麼叫你 ──
  // 泡泡第一句先接受上一頁你給的叫法（命名儀式的回應），第二句才問你。
  // 刻意不自稱名字（「{name} 以後要怎麼叫你？」是在叫自己，見角色指南）。
  Widget _buildNicknamePage() {
    return _mascotPage(
      emotion: 'expect',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _speechBubble(_l10n.obNicknameBubble),
          const SizedBox(height: 24),
          TextField(
            controller: _nicknameController,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18),
            maxLength: 12,
            decoration: InputDecoration(
              hintText: _l10n.obNicknameHint,
              counterText: '',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.orange.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Colors.orange),
              ),
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _nicknameController.text.trim().isEmpty
                  ? null
                  : () {
                      setState(
                        () => _nickname = _nicknameController.text.trim(),
                      );
                      _nextPage();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                disabledBackgroundColor: AppInk.faint,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                _l10n.obNext,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 功能引導三頁共用：預設開啟的單一問題。
  // 「好」= 開啟並前進；紅色「不用了」= 跳確認框，確定才關閉並前進。
  Widget _buildHabitPickerPage() {
    return _mascotPage(
      emotion: 'smile',
      // 兔咪大小跟引導頁其他頁面統一（不再壓縮為 140）。內容若超出（小機型 + freq 全選）
      // 走 ClampingScrollPhysics 正常 scroll
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _speechBubble(_l10n.obHabitBubble),
          const SizedBox(height: 8),
          Text(
            _l10n.obHabitLaterHint,
            style: const TextStyle(fontSize: 13, color: AppInk.faint),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _kOnboardingHabits
                .map((h) => _habitChip(h.name, h.emoji, h.freq))
                .toList(),
          ),
          _freqSection(),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _nextPage,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                _selectedHabits.isEmpty ? _l10n.commonSkip : _l10n.obNext,
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 已選取且適合頻率的習慣 → 顯示每日/每週切換
  Widget _freqSection() {
    final rows = _kOnboardingHabits
        .where((h) => h.freq && _selectedHabits.contains(h.name))
        .toList();
    return AnimatedSize(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final offset = Tween<Offset>(
            begin: const Offset(0, -0.08),
            end: Offset.zero,
          ).animate(animation);
          final scale = Tween<double>(begin: 0.98, end: 1).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: offset,
              child: ScaleTransition(scale: scale, child: child),
            ),
          );
        },
        child: rows.isEmpty
            ? const SizedBox.shrink(key: ValueKey('freq-empty'))
            : Container(
                key: const ValueKey('freq-panel'),
                width: double.infinity,
                margin: const EdgeInsets.only(top: 20),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.orange.shade100),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withValues(alpha: 0.10),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.repeat_rounded,
                          size: 15,
                          color: Colors.orange.shade700,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _l10n.obHabitFreqTitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ...rows.indexed.map(
                      (entry) => _animatedFreqRow(
                        entry.$1,
                        entry.$2.emoji,
                        entry.$2.name,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _animatedFreqRow(int index, String emoji, String name) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('freq-row-$name'),
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 260 + index * 45),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 8),
            child: child,
          ),
        );
      },
      child: _freqRow(emoji, name),
    );
  }

  Widget _freqRow(String emoji, String name) {
    final times = _weeklyTimes[name]; // null = 每日
    final isWeekly = times != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text('$emoji $name', style: const TextStyle(fontSize: 14)),
          ),
          // 每週（主要，可調次數）
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SizeTransition(
                  sizeFactor: animation,
                  axis: Axis.horizontal,
                  axisAlignment: 1,
                  child: child,
                ),
              );
            },
            child: isWeekly
                ? _weeklyStepper(name, times)
                : GestureDetector(
                    key: ValueKey('weekly-pill-$name'),
                    onTap: () {
                      _playOnboardingSfx(SfxCue.tap);
                      setState(() => _weeklyTimes[name] = 3);
                    },
                    child: _freqPill(_l10n.hsWeekly, false),
                  ),
          ),
          const SizedBox(width: 6),
          // 每日（次要，靠右）
          GestureDetector(
            onTap: () {
              if (isWeekly) _playOnboardingSfx(SfxCue.tap);
              setState(() => _weeklyTimes.remove(name));
            },
            child: _freqPill(_l10n.hsDaily, !isWeekly),
          ),
        ],
      ),
    );
  }

  // 每週次數調整器：−／＋ 改每週次數（1~7）
  Widget _weeklyStepper(String name, int times) {
    return Container(
      key: ValueKey('weekly-stepper-$name'),
      decoration: BoxDecoration(
        color: Colors.orange,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              _l10n.hsWeekly,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _stepBtn(Icons.remove, () {
            _playOnboardingSfx(SfxCue.tap);
            setState(() => _weeklyTimes[name] = (times - 1).clamp(1, 7));
          }),
          SizedBox(
            width: 34,
            child: Text(
              _l10n.obTimesPerWeek(times),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _stepBtn(Icons.add, () {
            _playOnboardingSfx(SfxCue.tap);
            setState(() => _weeklyTimes[name] = (times + 1).clamp(1, 7));
          }),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 34,
        height: 34,
        decoration: const BoxDecoration(
          color: Colors.white24,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 19, color: Colors.white),
      ),
    );
  }

  Widget _freqPill(String label, bool selected) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? Colors.orange : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? Colors.orange : const Color(0xFFDDD0C4),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: selected ? Colors.white : AppInk.soft,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }

  // 習慣選擇 Chip（可多選）
  Widget _habitChip(String name, String emoji, bool freq) {
    final selected = _selectedHabits.contains(name);
    return GestureDetector(
      onTap: () {
        _playOnboardingSfx(SfxCue.tap);
        setState(() {
          if (selected) {
            _selectedHabits.remove(name);
            _weeklyTimes.remove(name);
          } else {
            _selectedHabits.add(name);
            // 適合頻率的習慣預設為每週 3 次
            if (freq) _weeklyTimes[name] = 3;
          }
        });
      },
      child: AnimatedScale(
        scale: selected ? 1.04 : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.orange : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? Colors.orange : Colors.orange.shade100,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.orange.withValues(alpha: 0.20),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : const [],
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            style: TextStyle(
              color: selected ? Colors.white : AppInk.strong,
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Text('$emoji $name'),
                Positioned(
                  top: -12,
                  right: -14,
                  child: AnimatedScale(
                    scale: selected ? 1 : 0.65,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutBack,
                    child: AnimatedOpacity(
                      opacity: selected ? 1 : 0,
                      duration: const Duration(milliseconds: 140),
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.orange.withValues(alpha: 0.24),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // onboarding 用的單欄數字輸入（橘色風格）
  // iOS 純數字鍵盤沒有「完成」鍵，但因為鍵盤彈出時 _mascotPage 會
  // 把整層內容往上推（兔咪暫時被擠到畫面外），下方的「填寫完成 / 下次
  // 再說」按鈕都能點到，所以不再額外塞 suffix icon
  // ── 畫面5：進門 ──
  // 刻意不用「慢慢來」：那是安慰型台詞，只留給撤銷／久違回來／夜深／連續中斷。
  // 開場就用等於在安慰一個還不存在的焦慮（見角色指南「四種講法」）。
  Widget _buildDonePage() {
    return _mascotPage(
      emotion: 'pop_happy',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _speechBubble(_l10n.obDoneBubble(_nickname), fontSize: 18),
          const SizedBox(height: 48),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _finish,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 4,
                shadowColor: Colors.orange.withValues(alpha: 0.4),
              ),
              child: Text(
                _l10n.obStart,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _onboardingSoundButton() {
    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: AudioControlButton(
          style: AudioControlStyle.onboarding,
          accent: Colors.orange.shade700,
          onMusicEnabled: () => unawaited(_ensureOnboardingBgm(unmute: true)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 第1頁沒有返回按鈕；任何頁在追問子步驟時也要顯示返回
    final showBack = _currentPage > 0 || _pages[_currentPage].inSubStep();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // 引導頁背景是 #FFF8F0 米黃淡色，預設 iOS status bar 是淺色字會看不見
      // 時間/訊號/電量。強制 dark icons（深色字）才看得清楚
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: const Color(0xFFFFF8F0),
        // 進度點指示器
        bottomNavigationBar: Container(
          height: 48,
          color: const Color(0xFFFFF8F0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_pages.length, (i) {
              final active = i == _currentPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: active ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: active ? Colors.orange : Colors.orange.shade200,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Image.asset(
                  'assets/scenes/onboarding/onboarding_bg_v3.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFFFFF8F0).withValues(alpha: 0.12),
                        Colors.white.withValues(alpha: 0.10),
                        const Color(0xFFFFF8F0).withValues(alpha: 0.34),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            // 隱形預渲染抵達頁的台詞，讓字形提前載入 GPU 圖集，避免首次顯示亂碼
            Offstage(
              child: Text(
                _l10n.obArrivalLines,
                style: const TextStyle(fontSize: 18),
              ),
            ),
            PageView(
              controller: _pageController,
              // 禁止滑動（只能用按鈕前進）
              physics: const NeverScrollableScrollPhysics(),
              children: [for (final p in _pages) p.build()],
            ),
            _onboardingSoundButton(),
            // 返回按鈕：浮在主畫面上層，不佔排版空間，避免內容下移
            if (showBack)
              SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.orange,
                    ),
                    onPressed: _handleBack,
                    tooltip: _l10n.obBack,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
