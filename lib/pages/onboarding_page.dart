import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/bgm_service.dart';
import '../utils/input_formatters.dart';
import '../utils/lenient_date.dart';
import '../utils/mascot.dart';
import '../utils/prefs_keys.dart';
import '../utils/sfx_service.dart';
import '../utils/units.dart';
import '../utils/user_validators.dart';
import '../utils/weight_records.dart';
import '../widgets/audio_control_button.dart';
import '../widgets/birthday_picker.dart';
import '../widgets/mascot_scene.dart';

// 引導頁「習慣選擇」清單（喝水交由畫面4處理，故不列入）
// freq=true：適合「每週幾次」的習慣，選取後會出現每日/每週切換
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

class _OnboardingPageState extends State<OnboardingPage>
    with WidgetsBindingObserver {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // 身體資訊頁專用 scroll controller：鍵盤彈出時自動捲到底，把按鈕推到鍵盤上緣
  // （兔咪會被擠到畫面外，但這頁欄位/按鈕優先）
  final ScrollController _bodyInfoScrollCtrl = ScrollController();

  // 畫面1：打字動畫
  final List<String> _lines = ['嗯...你來了。', '我平常有點愛睡。', '你想開始時，我會陪你。'];
  int _lineIndex = 0;
  String _displayText = '';
  bool _page1Done = false;
  Timer? _typingTimer;

  // 畫面2：吉祥物名稱
  final TextEditingController _mascotController = TextEditingController(
    text: '兔咪',
  );
  // 骰子隨機名字用：可愛、好唸、之後多語也通用的小名池
  static const List<String> _mascotNamePool = [
    '兔咪',
    '啾啾',
    '糰子',
    '麻糬',
    '棉花糖',
    '雪球',
    '紅豆',
    '布丁',
    '奶茶',
    '咪寶',
    '跳跳',
    '阿白',
    '泡泡',
    '小雲',
    '朵朵',
    '星星',
    '小月',
    '晴晴',
    '露露',
    '糖糖',
    '蜜糖',
    '奶油',
    '可可',
    '芝麻',
    '豆花',
    '柚子',
    '小桃',
    '小栗',
    '小米',
    '米糰',
    '布布',
    '啵啵',
    '圓圓',
    '毛球',
    '小鈴',
    '小燈',
    '萌萌',
    '軟糖',
    '奶泡',
    '白白',
  ];
  final math.Random _nameRng = math.Random();

  // 畫面3：用戶暱稱
  final TextEditingController _nicknameController = TextEditingController();
  String _mascotName = '兔咪';

  // 畫面4/5/6：功能引導（預設開啟，按「不用了」確認後才關）
  bool? _waterEnabled;
  bool? _timerEnabled;
  bool? _familyEnabled;

  // 畫面7：身體資訊
  String _gender = '';
  // 身高（metric: cm；imperial: ft + 額外的 _heightInController 是 in）
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _heightInController = TextEditingController();
  // 體重 / 目標體重（依當下單位是 kg 或 lb）
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _targetWeightController = TextEditingController();
  final TextEditingController _birthdayController = TextEditingController();
  // FocusNode 用來讓「紅字錯誤訊息 + 兔咪比例怪」只在欄位失焦後才顯示。
  // 還在編輯中（hasFocus）就先收起警告，避免使用者打到一半被吐槽
  final FocusNode _heightFocus = FocusNode();
  final FocusNode _heightInFocus = FocusNode();
  final FocusNode _weightFocus = FocusNode();
  final FocusNode _targetWeightFocus = FocusNode();
  final FocusNode _birthdayFocus = FocusNode();
  UnitSystem _unit = UnitSystem.metric;
  DateTime? _birthday; // 生日
  // 活動量（內部仍用久坐/輕度/中度/高度）— 跟 profile_edit_page 共用 key 與選項
  String _activityLevel = '';

  // 活動量選項 → 前端顯示為一週運動天數。跟 profile_edit_page 那邊保持同步，
  // 改一邊另一邊要記得跟著改（值會被 water_page / weight_page 拿去算 TDEE 與每日水量）
  static const Map<String, String> _activityDayLabels = {
    '久坐': '幾乎沒有',
    '輕度': '1-2 天',
    '中度': '3-4 天',
    '高度': '5 天以上',
  };

  // 用戶暱稱（畫面3填完後存起來）
  String _nickname = '';

  // ── 頁面定義表：頁數、順序、返回鍵的子步驟邏輯都從這裡推導 ──
  // 新增/刪除頁面只要改這張表，進度點數量與換頁邊界會自動跟上。
  // inSubStep 回 true 時返回鍵先退出追問子步驟（exitSubStep）而不換頁。
  late final List<
    ({
      Widget Function() build,
      bool Function() inSubStep,
      VoidCallback exitSubStep,
    })
  >
  _pages = [
    (build: _buildPage1, inSubStep: _noSubStep, exitSubStep: _noopSubStep),
    (build: _buildPage2, inSubStep: _noSubStep, exitSubStep: _noopSubStep),
    (build: _buildPage3, inSubStep: _noSubStep, exitSubStep: _noopSubStep),
    (build: _buildPage4, inSubStep: _noSubStep, exitSubStep: _noopSubStep),
    (build: _buildPage5, inSubStep: _noSubStep, exitSubStep: _noopSubStep),
    (build: _buildFamilyPage, inSubStep: _noSubStep, exitSubStep: _noopSubStep),
    (
      build: _buildHabitPickerPage,
      inSubStep: _noSubStep,
      exitSubStep: _noopSubStep,
    ),
    (build: _buildPage6, inSubStep: _noSubStep, exitSubStep: _noopSubStep),
    (build: _buildPage7, inSubStep: _noSubStep, exitSubStep: _noopSubStep),
  ];

  static bool _noSubStep() => false;
  static void _noopSubStep() {}

  // 身體資訊頁：使用者按過一次「填寫完成」後變 true。
  // 行為：按鈕永遠可按，按下去才檢查必填；空著的必填欄會跳「請填寫 X」紅字。
  bool _bodyInfoSubmitAttempted = false;
  // 各欄位「失焦過一次」= 視為輸入完畢，從那刻開始可以跳範圍/比例提示。
  // 不等到提交才警告，讓使用者填到下一格時就看到上一格的問題。
  bool _heightTouched = false;
  bool _weightTouched = false;
  bool _targetWeightTouched = false;
  bool _birthdayTouched = false;

  // 習慣選擇頁：使用者勾選的習慣名稱
  final Set<String> _selectedHabits = {};
  // 習慣選擇頁：設為「每週」的習慣 → 名稱對應每週次數；未列入者為每日
  final Map<String, int> _weeklyTimes = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nicknameController.addListener(() => setState(() {}));
    _heightController.addListener(() => setState(() {}));
    _heightInController.addListener(() => setState(() {}));
    _weightController.addListener(() => setState(() {}));
    _targetWeightController.addListener(() => setState(() {}));
    // 焦點變化：失焦時設 touched 旗標（= 該欄輸入完畢），rebuild 顯示對應提示
    _heightFocus.addListener(() {
      if (!_heightFocus.hasFocus) {
        setState(() => _heightTouched = true);
      } else {
        setState(() {});
      }
    });
    _heightInFocus.addListener(() {
      if (!_heightInFocus.hasFocus) {
        setState(() => _heightTouched = true);
      } else {
        setState(() {});
      }
    });
    _weightFocus.addListener(() {
      if (!_weightFocus.hasFocus) {
        setState(() => _weightTouched = true);
      } else {
        setState(() {});
      }
    });
    _targetWeightFocus.addListener(() {
      if (!_targetWeightFocus.hasFocus) {
        setState(() => _targetWeightTouched = true);
      } else {
        setState(() {});
      }
    });
    _birthdayFocus.addListener(() {
      if (!_birthdayFocus.hasFocus) {
        setState(() => _birthdayTouched = true);
      } else {
        setState(() {});
      }
    });
    _loadUnit();
    // 等第一幀渲染完成（Offstage 預熱字形後）再啟動打字動畫
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startTyping();
    });
  }

  Future<void> _loadUnit() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _unit = UnitSystem.load(prefs));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _typingTimer?.cancel();
    _pageController.dispose();
    _mascotController.dispose();
    _nicknameController.dispose();
    _heightController.dispose();
    _heightInController.dispose();
    _weightController.dispose();
    _targetWeightController.dispose();
    _birthdayController.dispose();
    _heightFocus.dispose();
    _heightInFocus.dispose();
    _weightFocus.dispose();
    _targetWeightFocus.dispose();
    _birthdayFocus.dispose();
    _bodyInfoScrollCtrl.dispose();
    super.dispose();
  }

  // 鍵盤狀態變化時，把身體資訊頁的 scroll view 跟著捲到底
  // ─ iOS 鍵盤動畫期間 didChangeMetrics 會連發多次（viewport 漸縮）
  // ─ 改用 jumpTo 每次同步跳到當前 maxScrollExtent，視覺上跟鍵盤同步上來
  //   （比 animateTo 等鍵盤動畫跑完再起一段動畫快很多）
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_bodyInfoScrollCtrl.hasClients) return;
      final kb = MediaQueryData.fromView(View.of(context)).viewInsets.bottom;
      if (kb > 0) {
        _bodyInfoScrollCtrl.jumpTo(
          _bodyInfoScrollCtrl.position.maxScrollExtent,
        );
      }
    });
  }

  // 逐字打字效果
  void _startTyping() {
    if (!mounted) return;
    if (_lineIndex >= _lines.length) {
      setState(() => _page1Done = true);
      return;
    }
    final chars = _lines[_lineIndex].characters.toList(); // 預先拆好，避免每次重建
    var charIndex = 0;
    setState(() => _displayText = '');
    _typingTimer?.cancel();
    _typingTimer = Timer.periodic(const Duration(milliseconds: 60), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (charIndex < chars.length) {
        setState(() => _displayText = chars.take(charIndex + 1).join());
        charIndex++;
      } else {
        timer.cancel();
        Future.delayed(const Duration(milliseconds: 900), () {
          if (!mounted) return;
          _lineIndex++;
          _startTyping();
        });
      }
    });
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

  // 從目前單位的輸入欄推回公制
  double? _heightCm() {
    if (_unit == UnitSystem.imperial) {
      final ft = int.tryParse(_heightController.text.trim());
      final inches = int.tryParse(_heightInController.text.trim());
      if (ft == null && inches == null) return null;
      return UnitConvert.ftInToCm(ft ?? 0, inches ?? 0);
    }
    return double.tryParse(_heightController.text.trim());
  }

  double? _weightKgFromCtrl(TextEditingController c) {
    final v = double.tryParse(c.text.trim());
    if (v == null) return null;
    if (_unit == UnitSystem.imperial) return UnitConvert.lbToKg(v);
    return v;
  }

  // 「Raw」版 = 不管焦點，純驗證，用於 _bodyInfoFilled 決定按鈕能不能按。
  // 顯示版（不帶 Raw 後綴）多包一層：焦點還在欄位上就 return null，避免使用者
  // 還在打字就被吐槽「請輸入 X 到 Y」。離開焦點才會看到提示。
  String? get _heightErrTextRaw {
    if (_unit == UnitSystem.imperial) {
      if (_heightController.text.trim().isEmpty &&
          _heightInController.text.trim().isEmpty) {
        return null;
      }
      return UserValidators.heightCm(_heightCm());
    }
    return UserValidators.height(_heightController.text);
  }

  String? get _weightErrTextRaw =>
      UserValidators.weightIn(_weightController.text, _unit);
  String? get _targetWeightErrTextRaw =>
      UserValidators.targetWeightIn(_targetWeightController.text, _unit);

  // 「輸入完畢」= 該欄失焦過、或使用者按過「填寫完成」
  bool get _heightInputFinished => _heightTouched || _bodyInfoSubmitAttempted;
  bool get _weightInputFinished => _weightTouched || _bodyInfoSubmitAttempted;
  bool get _targetWeightInputFinished =>
      _targetWeightTouched || _bodyInfoSubmitAttempted;

  // 兩格都「輸入完畢」+ 各自在合理範圍 + BMI 超出 → 比例異常
  bool _isBmiPairOddRaw() {
    final cm = _heightCm();
    final kg = _weightKgFromCtrl(_weightController);
    if (cm == null || kg == null) return false;
    if (cm < UserRanges.heightMinCm || cm > UserRanges.heightMaxCm) {
      return false;
    }
    if (kg < UserRanges.weightMinKg || kg > UserRanges.weightMaxKg) {
      return false;
    }
    final hM = cm / 100;
    final bmi = kg / (hM * hM);
    return bmi < UserRanges.bmiMin || bmi > UserRanges.bmiMax;
  }

  bool get _bmiOddVisible {
    // 任一格還在編輯就不顯示「比例異常」/ 兔咪不變 sad
    if (_heightFocus.hasFocus ||
        _heightInFocus.hasFocus ||
        _weightFocus.hasFocus) {
      return false;
    }
    return _heightInputFinished && _weightInputFinished && _isBmiPairOddRaw();
  }

  String? get _heightErrText {
    // 正在編輯就不顯示（不管之前 touched 過沒，重新進來改也算「還在改」）
    if (_heightFocus.hasFocus || _heightInFocus.hasFocus) return null;
    if (!_heightInputFinished) return null;
    if (_bodyInfoSubmitAttempted && !_hasHeightInput) return '請填寫身高';
    final raw = _heightErrTextRaw;
    if (raw != null) return raw;
    if (_bmiOddVisible) return '比例異常';
    return null;
  }

  String? get _weightErrText {
    if (_weightFocus.hasFocus) return null;
    if (!_weightInputFinished) return null;
    if (_bodyInfoSubmitAttempted && _weightController.text.trim().isEmpty) {
      return '請填寫體重';
    }
    final raw = _weightErrTextRaw;
    if (raw != null) return raw;
    if (_bmiOddVisible) return '比例異常';
    return null;
  }

  String? get _targetWeightErrText {
    if (_targetWeightFocus.hasFocus) return null;
    if (!_targetWeightInputFinished) return null;
    return _targetWeightErrTextRaw;
  }

  // 性別/生日是非 TextField 控制項（chip / picker），用獨立 helper 顯示紅字
  String? get _genderError {
    if (_bodyInfoSubmitAttempted && _gender.isEmpty) return '請選擇性別';
    return null;
  }

  String? get _birthdayError {
    final raw = _birthdayController.text.trim();
    final shouldValidate =
        _bodyInfoSubmitAttempted ||
        _birthdayTouched ||
        !_birthdayFocus.hasFocus;
    if (_bodyInfoSubmitAttempted && raw.isEmpty) return '請填寫生日';
    if (raw.isEmpty || !shouldValidate) return null;

    final parsed = parseLenientDate(raw);
    if (parsed == null) return '看不懂這個日期，試試 2000-1-1 或 20000101';
    return _birthdayDateError(parsed);
  }

  DateTime get _birthdayFirstDate {
    final now = DateTime.now();
    return DateTime(now.year - UserRanges.birthdayMaxAgeYears);
  }

  DateTime get _birthdayLastDate => DateTime.now();

  String _birthdayText(DateTime value) =>
      '${value.year}-${value.month}-${value.day}';

  String? _birthdayDateError(DateTime value) {
    if (value.isBefore(_birthdayFirstDate) ||
        value.isAfter(_birthdayLastDate)) {
      return '日期超出可選範圍';
    }
    return UserValidators.birthday(value);
  }

  void _setBirthday(DateTime value) {
    _birthday = value;
    _birthdayController.text = _birthdayText(value);
    _birthdayController.selection = TextSelection.collapsed(
      offset: _birthdayController.text.length,
    );
  }

  DateTime _birthdayPickerInitialDate() {
    final rawDate = parseLenientDate(_birthdayController.text);
    final candidate =
        _birthday ?? rawDate ?? DateTime(DateTime.now().year - 20);
    if (candidate.isBefore(_birthdayFirstDate)) return _birthdayFirstDate;
    if (candidate.isAfter(_birthdayLastDate)) return _birthdayLastDate;
    return candidate;
  }

  // 點生日欄 → 直接開月曆系統選日期。
  Future<void> _openBirthdayPicker() async {
    _playOnboardingSfx(SfxCue.tap);
    FocusScope.of(context).unfocus();
    final picked = await showBirthdayPicker(
      context,
      initial: _birthdayPickerInitialDate(),
      firstDate: _birthdayFirstDate,
      lastDate: _birthdayLastDate,
      accent: Colors.orange,
    );
    if (picked == null || !mounted) return;
    _playOnboardingSfx(SfxCue.success);
    setState(() {
      _birthdayTouched = true;
      _setBirthday(picked);
    });
  }

  // 觸發提交：按鈕永遠可按，按下去先檢查再決定要不要進下一步
  void _tryFinishBodyInfo() {
    setState(() => _bodyInfoSubmitAttempted = true);
    if (_bodyInfoFilled) {
      _playOnboardingSfx(SfxCue.success);
      _nextPage(playSound: false);
    } else {
      _playOnboardingSfx(SfxCue.cancel);
    }
    // 若驗證沒過，留在本頁；setState 已觸發，紅字會跑出來
  }

  bool get _hasHeightInput {
    if (_unit == UnitSystem.imperial) {
      return _heightController.text.trim().isNotEmpty ||
          _heightInController.text.trim().isNotEmpty;
    }
    return _heightController.text.trim().isNotEmpty;
  }

  // 建議不是錯誤訊息：身高一合理就出現，不等「填寫完成」；
  // 比例明顯不合理時收起（統一規則見 HealthAdvice）
  ({int low, int high, int suggest, String unit})?
  get _targetWeightSuggestion => HealthAdvice.targetWeightSuggestion(
    heightCm: _heightErrTextRaw == null ? _heightCm() : null,
    weightKg: _weightErrTextRaw == null
        ? _weightKgFromCtrl(_weightController)
        : null,
    system: _unit,
  );

  // 目標體重建議：依身高的健康 BMI 範圍（18.5–24），建議值取 BMI 22
  Widget _targetWeightHint() {
    final suggestion = _targetWeightSuggestion;
    if (suggestion == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(Icons.favorite_outline, size: 14, color: Colors.orange.shade400),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              '健康體重約 ${suggestion.low}–${suggestion.high} ${suggestion.unit}',
              style: const TextStyle(fontSize: 12, color: AppInk.soft),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _targetWeightSuggestSuffix() {
    final suggestion = _targetWeightSuggestion;
    if (suggestion == null) return null;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TextButton(
        onPressed: () {
          _playOnboardingSfx(SfxCue.tap);
          setState(
            () => _targetWeightController.text = suggestion.suggest.toString(),
          );
        },
        style: TextButton.styleFrom(
          foregroundColor: Colors.orange.shade800,
          backgroundColor: Colors.orange.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.orange.shade200),
          ),
        ),
        child: Text(
          '建議 ${suggestion.suggest}${suggestion.unit}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  bool get _bodyInfoFilled {
    final cm = _heightCm();
    final kg = _weightKgFromCtrl(_weightController);
    final hasHeight = _unit == UnitSystem.imperial
        ? (_heightController.text.trim().isNotEmpty ||
              _heightInController.text.trim().isNotEmpty)
        : _heightController.text.trim().isNotEmpty;
    if (!_gender.isNotEmpty) return false;
    if (!hasHeight) return false;
    if (_weightController.text.trim().isEmpty) return false;
    if (_birthday == null) return false;
    // 按鈕啟用判定不看焦點：使用者就算還在輸入框內，數值錯就不准進下一步
    if (_heightErrTextRaw != null) return false;
    if (_weightErrTextRaw != null) return false;
    if (_targetWeightErrTextRaw != null) return false;
    if (UserValidators.birthday(_birthday) != null) return false;
    // BMI 比例檢查（用公制換算）
    if (cm != null && kg != null && cm > 0) {
      final hM = cm / 100;
      final bmi = kg / (hM * hM);
      if (bmi < UserRanges.bmiMin || bmi > UserRanges.bmiMax) return false;
    }
    return true;
  }

  // 兔咪 sad 跟對話切換，跟欄位下方紅字共用同一個顯示條件
  bool get _bmiOddOnboarding => _bmiOddVisible;

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
          ? '兔咪'
          : _mascotController.text.trim(),
    );
    await prefs.setString(
      PrefsKeys.userNickname,
      _nicknameController.text.trim().isEmpty
          ? '你'
          : _nicknameController.text.trim(),
    );
    await prefs.setBool(PrefsKeys.waterEnabled, _waterEnabled ?? false);
    await prefs.setBool(PrefsKeys.timerEnabled, _timerEnabled ?? false);
    await prefs.setBool(PrefsKeys.familyEnabled, _familyEnabled ?? false);

    // 身體資訊
    if (_gender.isNotEmpty) {
      await prefs.setString(PrefsKeys.userGender, _gender);
    }
    final heightCm = _heightCm();
    if (heightCm != null &&
        heightCm >= UserRanges.heightMinCm &&
        heightCm <= UserRanges.heightMaxCm) {
      await prefs.setDouble(PrefsKeys.userHeight, heightCm);
    }
    // 體重功能預設開啟：就算使用者略過填寫也開著（之後仍可在設定關閉）
    await prefs.setBool(PrefsKeys.weightTrackingEnabled, true);
    final weightKg = _weightKgFromCtrl(_weightController);
    if (weightKg != null &&
        weightKg >= UserRanges.weightMinKg &&
        weightKg <= UserRanges.weightMaxKg) {
      await prefs.setDouble(PrefsKeys.userWeight, weightKg);
      await upsertSavedWeightRecord(prefs, weightKg: weightKg);
      // 有填才自動新增體重紀錄習慣
      await _addWeightHabit(prefs);
      await syncWeightHabitForDate(prefs);
    }
    final targetKg = _weightKgFromCtrl(_targetWeightController);
    if (targetKg != null &&
        targetKg >= UserRanges.targetWeightMinKg &&
        targetKg <= UserRanges.targetWeightMaxKg) {
      await prefs.setDouble(PrefsKeys.targetWeight, targetKg);
    }
    // 選了喝水功能 → 自動加入「喝足夠的水」習慣
    if (_waterEnabled == true) _selectedHabits.add('喝足夠的水');
    // 引導頁「習慣選擇頁」勾選的習慣
    await _addPickedHabits(prefs);

    // 生日以 yyyy-MM-dd 格式儲存
    if (_birthday != null) {
      final b = _birthday!;
      await prefs.setString(
        PrefsKeys.userBirthday,
        '${b.year.toString().padLeft(4, '0')}-'
        '${b.month.toString().padLeft(2, '0')}-'
        '${b.day.toString().padLeft(2, '0')}',
      );
    }
    // 活動量（選填）— water/weight 頁讀 user_activity_level 算 TDEE 與每日水量
    if (_activityLevel.isNotEmpty) {
      await prefs.setString(PrefsKeys.userActivityLevel, _activityLevel);
    }

    if (!mounted) return;
    // 切換 BGM 到主 app 曲目（cross-fade）
    unawaited(BgmService.instance.play('sounds/bgm_main.m4a'));
    unawaited(Navigator.of(context).pushReplacementNamed('/home'));
  }

  // 在習慣清單自動新增體重紀錄
  Future<void> _addWeightHabit(SharedPreferences prefs) async {
    await ensureWeightHabit(prefs);
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

  // 選項按鈕
  Widget _optionButton(String label, VoidCallback onTap, {Color? color}) {
    final accent = color ?? Colors.orange;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
        shadowColor: accent.withValues(alpha: 0.22),
        elevation: 1.5,
        child: InkWell(
          onTap: () {
            _playOnboardingSfx(SfxCue.tap);
            unawaited(_ensureOnboardingBgm());
            onTap();
          },
          borderRadius: BorderRadius.circular(16),
          splashColor: accent.withValues(alpha: 0.10),
          highlightColor: accent.withValues(alpha: 0.06),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withValues(alpha: 0.24)),
              // 純色 accent 淡底（不再用 gradient，避免兩端白氣感）
              color: accent.withValues(alpha: 0.10),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.2,
                color: accent == Colors.orange
                    ? Colors.orange.shade800
                    : accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
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
  }) {
    return GestureDetector(
      // 點空白處收起鍵盤
      onTap: () => FocusScope.of(context).unfocus(),
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

  Widget _buildPage1() {
    // 依打字進度切換情緒：第1句剛醒(wake) → 自我介紹(neutral) → 陪伴宣告(smile)
    final wakeEmotion = _page1Done
        ? 'smile'
        : (_lineIndex == 0
              ? 'wake'
              : (_lineIndex == 1 ? 'neutral_front' : 'smile'));
    return _mascotPage(
      emotion: wakeEmotion,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _speechBubble(_displayText, fontSize: 18),
          const SizedBox(height: 40),
          // 打字完成後才出現「繼續」按鈕
          AnimatedOpacity(
            opacity: _page1Done ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 400),
            child: ElevatedButton(
              onPressed: _page1Done ? _nextPage : null,
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
              child: const Text(
                '繼續',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
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
      _mascotName = pick;
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

  // ── 畫面2：幫吉祥物命名 ──
  Widget _buildPage2() {
    return _mascotPage(
      emotion: 'smile',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _speechBubble('對了...\n你可以幫我取個名字。\n想不到的話，按旁邊骰子幫我抽一個。'),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _mascotController,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18),
                  maxLength: 12,
                  decoration: InputDecoration(
                    hintText: '幫我取個名字',
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
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                setState(
                  () => _mascotName = _mascotController.text.trim().isEmpty
                      ? '兔咪'
                      : _mascotController.text.trim(),
                );
                _nextPage();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                '下一步',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 畫面3：用戶暱稱 ──
  Widget _buildPage3() {
    return _mascotPage(
      emotion: 'expect',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _speechBubble('那...你呢？\n$_mascotName 以後要怎麼叫你？'),
          const SizedBox(height: 24),
          TextField(
            controller: _nicknameController,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18),
            maxLength: 12,
            decoration: InputDecoration(
              hintText: '輸入你的暱稱',
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
              child: const Text(
                '下一步',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 功能引導三頁共用：預設開啟的單一問題。
  // 「好」= 開啟並前進；紅色「不用了」= 跳確認框，確定才關閉並前進。
  Widget _featureIntroPage({
    required String bubble,
    required String acceptLabel,
    required VoidCallback onAccept,
    required String declineName,
    required VoidCallback onDeclineConfirmed,
  }) {
    return _mascotPage(
      emotion: 'neutral_front',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _speechBubble(bubble),
          const SizedBox(height: 32),
          _optionButton(acceptLabel, onAccept),
          _optionButton(
            '不用了',
            () => _confirmDecline(declineName, onDeclineConfirmed),
            color: Colors.red.shade400,
          ),
        ],
      ),
    );
  }

  // 按「不用了」跳確認框：確定才關閉（之後仍能在設定再開）。
  Future<void> _confirmDecline(String name, VoidCallback onConfirmed) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('確定先關掉$name嗎？'),
        content: const Text('之後想用，可以在「設定 → 功能開關」隨時打開喔。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('還是留著'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade400),
            child: const Text('確定關掉'),
          ),
        ],
      ),
    );
    if (ok == true) {
      _playOnboardingSfx(SfxCue.cancel);
      onConfirmed();
    }
  }

  // ── 畫面4：喝水功能引導 ──
  Widget _buildPage4() {
    return _featureIntroPage(
      bubble: '口渴前，我會輕輕提醒你喝水。\n先幫你開著好嗎？',
      acceptLabel: '好，幫我記',
      onAccept: () {
        setState(() => _waterEnabled = true);
        _nextPage(playSound: false);
      },
      declineName: '喝水提醒',
      onDeclineConfirmed: () {
        setState(() => _waterEnabled = false);
        _nextPage(playSound: false);
      },
    );
  }

  // ── 畫面5：專注計時功能引導 ──
  Widget _buildPage5() {
    return _featureIntroPage(
      bubble: '專心的時候，我幫你顧著時間。\n要先開著專注計時嗎？',
      acceptLabel: '好，開著',
      onAccept: () {
        setState(() => _timerEnabled = true);
        _nextPage(playSound: false);
      },
      declineName: '專注計時',
      onDeclineConfirmed: () {
        setState(() => _timerEnabled = false);
        _nextPage(playSound: false);
      },
    );
  }

  // ── 畫面6：家庭功能引導 ──
  Widget _buildFamilyPage() {
    return _featureIntroPage(
      bubble: '家裡有小朋友的話，\n我也能陪他們記小任務。\n要先開著嗎？',
      acceptLabel: '好，開著',
      onAccept: () {
        setState(() => _familyEnabled = true);
        _nextPage(playSound: false);
      },
      declineName: '家庭模式',
      onDeclineConfirmed: () {
        setState(() => _familyEnabled = false);
        _nextPage(playSound: false);
      },
    );
  }

  // ── 畫面7：身體資訊（可跳過）──
  // 結構：頂部兔咪+對話 + 可滾動欄位區 + 底部固定按鈕（避免下次再說被擠到 fold 下方）
  // 習慣選擇頁：勾選想養成的習慣，完成後寫入習慣清單
  Widget _buildHabitPickerPage() {
    return _mascotPage(
      emotion: 'smile',
      // 兔咪大小跟引導頁其他頁面統一（不再壓縮為 140）。內容若超出（小機型 + freq 全選）
      // 走 ClampingScrollPhysics 正常 scroll
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _speechBubble('要不要先放幾個小習慣？\n之後都可以再改。'),
          const SizedBox(height: 16),
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
                _selectedHabits.isEmpty ? '略過' : '下一步',
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
                          '想多久做一次？',
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
                    child: _freqPill('每週', false),
                  ),
          ),
          const SizedBox(width: 6),
          // 每日（次要，靠右）
          GestureDetector(
            onTap: () {
              if (isWeekly) _playOnboardingSfx(SfxCue.tap);
              setState(() => _weeklyTimes.remove(name));
            },
            child: _freqPill('每日', !isWeekly),
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
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '每週',
              style: TextStyle(
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
              '$times 次',
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
  Widget _onboardingNumField({
    required TextEditingController controller,
    required String label,
    String? errorText,
    Widget? suffixWidget,
    FocusNode? focusNode,
    // 非 null 時掛上自動補小數（只在公制欄位傳，傳該欄位的公制合理上限）
    num? decimalMax,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        // 公制：bodyMetricFormatter（含自動補小數，例 1708→170.8）
        // 英制 / 無 max：維持原本 3 位整數上限
        if (decimalMax != null)
          bodyMetricFormatter(decimalMax)
        else
          maxValueFormatter(999),
      ],
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        suffixIcon: suffixWidget,
        suffixIconConstraints: const BoxConstraints(),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.orange.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.orange),
        ),
      ),
    );
  }

  // imperial 模式的 ft/in 兩欄並排
  Widget _onboardingFtInRow() {
    InputDecoration deco(String label, String suffix) => InputDecoration(
      labelText: label,
      suffixText: suffix,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.orange.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.orange),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _heightController,
                focusNode: _heightFocus,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                decoration: deco('身高', 'ft'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _heightInController,
                focusNode: _heightInFocus,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                decoration: deco(' ', 'in'),
              ),
            ),
          ],
        ),
        if (_heightErrText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              _heightErrText!,
              style: TextStyle(color: Colors.red.shade700, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _buildPage6() {
    final bmiOdd = _bmiOddOnboarding;
    final emotion = bmiOdd ? 'sad' : 'smile';
    final bubbleText = bmiOdd ? '嗯…這比例怪怪的，再看一下？' : '我可以幫你紀錄身高、體重喔！';

    return _mascotPage(
      emotion: emotion,
      scrollController: _bodyInfoScrollCtrl,
      // 緊湊：兔咪間距 + padding 縮小，盡量單頁能塞下完整身體資訊
      mascotBottomSpacing: 8,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _speechBubble(bubbleText),
          const SizedBox(height: 14),
          // 性別選擇
          Row(
            children: [
              Text(
                '性別',
                style: TextStyle(
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 16),
              _genderChip('男'),
              const SizedBox(width: 8),
              _genderChip('女'),
              const SizedBox(width: 8),
              _genderChip('不透露'),
            ],
          ),
          if (_genderError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                _genderError!,
                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
              ),
            ),
          // 活動量（選填）— 跟性別放一起，兩個都是 chip 選擇器，視覺一致
          _onboardingActivitySelector(),
          const SizedBox(height: 12),
          // 身高（依單位顯示一格或兩格）
          if (_unit == UnitSystem.imperial)
            _onboardingFtInRow()
          else
            _onboardingNumField(
              controller: _heightController,
              focusNode: _heightFocus,
              label: '身高（cm）',
              errorText: _heightErrText,
              decimalMax: UserRanges.heightMaxCm,
            ),
          const SizedBox(height: 10),
          // 體重
          _onboardingNumField(
            controller: _weightController,
            focusNode: _weightFocus,
            label: '體重（${UnitFormat.weightLabel(_unit)}）',
            errorText: _weightErrText,
            // 英制(lb)不補小數
            decimalMax: _unit == UnitSystem.imperial
                ? null
                : UserRanges.weightMaxKg,
          ),
          const SizedBox(height: 10),
          // 目標體重（選填）
          _onboardingNumField(
            controller: _targetWeightController,
            focusNode: _targetWeightFocus,
            label: '目標體重（${UnitFormat.weightLabel(_unit)}，選填）',
            errorText: _targetWeightErrText,
            suffixWidget: _targetWeightSuggestSuffix(),
            decimalMax: _unit == UnitSystem.imperial
                ? null
                : UserRanges.targetWeightMaxKg,
          ),
          _targetWeightHint(),
          const SizedBox(height: 10),
          // 生日：整欄可點，直接跳出月曆系統（不打字、不彈鍵盤）。
          TextField(
            controller: _birthdayController,
            focusNode: _birthdayFocus,
            readOnly: true,
            showCursor: false,
            onTap: _openBirthdayPicker,
            decoration: InputDecoration(
              labelText: '生日',
              hintText: '點這裡選生日',
              errorText: _birthdayError,
              errorMaxLines: 2,
              suffixIcon: const Icon(
                Icons.calendar_today_outlined,
                size: 18,
                color: Colors.orange,
              ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.orange.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.orange),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              // 按鈕永遠可按，按下去才驗證。空著 / 超範圍會跳紅字提示
              onPressed: _tryFinishBodyInfo,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text(
                '填寫完成',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
          TextButton(
            onPressed: _nextPage,
            child: const Text('下次再說', style: TextStyle(color: AppInk.soft)),
          ),
        ],
      ),
    );
  }

  // 性別選擇按鈕
  Widget _genderChip(String label) {
    final selected = _gender == label;
    return GestureDetector(
      onTap: () {
        if (!selected) _playOnboardingSfx(SfxCue.tap);
        setState(() => _gender = label);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.orange : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.orange : const Color(0xFFDDD0C4),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppInk.soft,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  // 活動量 chip（樣式跟 _genderChip 一致）
  Widget _activityChip(String label) {
    final selected = _activityLevel == label;
    return GestureDetector(
      onTap: () {
        if (!selected) _playOnboardingSfx(SfxCue.tap);
        setState(() => _activityLevel = label);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.orange : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.orange : const Color(0xFFDDD0C4),
          ),
        ),
        child: Text(
          _activityDayLabels[label] ?? label,
          style: TextStyle(
            color: selected ? Colors.white : AppInk.soft,
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // 活動量選擇區：用「一週運動幾天」取代抽象的輕度/中度。
  Widget _onboardingActivitySelector() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '一週大概運動幾天？',
            style: TextStyle(
              color: Colors.orange.shade800,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: _activityDayLabels.keys.map(_activityChip).toList(),
          ),
        ],
      ),
    );
  }

  // ── 畫面7：收尾 ──
  Widget _buildPage7() {
    return _mascotPage(
      emotion: 'pop_happy',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _speechBubble('好了，$_nickname。\n我會在這裡陪你慢慢來。', fontSize: 18),
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
              child: const Text(
                '開始',
                style: TextStyle(
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
            // 隱形預渲染所有打字文字，讓字形提前載入 GPU 圖集，避免首次顯示亂碼
            Offstage(
              child: Text(_lines.join(), style: const TextStyle(fontSize: 18)),
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
                    tooltip: '回上一步',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
