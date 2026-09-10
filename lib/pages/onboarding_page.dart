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
import '../utils/lenient_date.dart';
import '../utils/mascot.dart';
import '../utils/prefs_keys.dart';
import '../utils/sfx_service.dart';
import '../utils/units.dart';
import '../utils/user_validators.dart';
import '../utils/weight_records.dart';
import '../widgets/app_pressable.dart';
import '../widgets/audio_control_button.dart';
import '../widgets/birthday_picker.dart';
import '../widgets/mascot_scene.dart';
import '../widgets/timer_ring_painter.dart';

// 引導頁「習慣選擇」清單（喝水交由畫面4處理，故不列入）
// freq=true：適合「每週幾次」的習慣，選取後會出現每日/每週切換
//
// name 沒有走 l10n：這些名稱選取後會直接存成習慣名，而首頁的去重與
// 喝水／體重連動判定都比對它（見 kHomePresets）。翻譯會讓連動失效。
// 詳見 docs/engineering_guardrails.md §i18n 刻意不遷。
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
  bool _pageMoving = false;
  bool _reduceMotion = false;

  // 身體資訊頁保留自己的閱讀位置；EditableText 負責將目前欄位捲入可視區，
  // 不再於每次鍵盤動畫強制跳到底（那會把正在填寫的身高欄推離畫面）。
  final ScrollController _bodyInfoScrollCtrl = ScrollController();

  // 畫面1：打字動畫
  final List<String> _lines = ['嗯...你來了。', '我平常有點愛睡。', '你想開始時，我會陪你。'];
  int _lineIndex = 0;
  String _displayText = '';
  bool _page1Done = false;
  Timer? _typingTimer;

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
  String _mascotName = '';

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

  // 活動量的儲存值（water_page / weight_page 拿去算 TDEE 與每日水量時比對
  // 這些中文字串），i18n 只換顯示標籤、不動儲存值。與 profile_edit_page 同步。
  static const List<String> _activityLevels = ['久坐', '輕度', '中度', '高度'];

  String _activityLabel(String value) => switch (value) {
    '久坐' => _l10n.activityAlmostNone,
    '輕度' => _l10n.activityDays1to2,
    '中度' => _l10n.activityDays3to4,
    _ => _l10n.activityDays5plus,
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion && !_page1Done) {
      _typingTimer?.cancel();
      _displayText = _lines.join('\n');
      _page1Done = true;
    }
    // 預設兔咪名走 l10n（英文介面是 Tumi）；只在還沒填過時帶入，
    // 不會蓋掉使用者已經打的字。
    if (!_mascotDefaultApplied) {
      _mascotDefaultApplied = true;
      _mascotController.text = _l10n.mascotDefaultName;
      _mascotName = _l10n.mascotDefaultName;
    }
  }

  @override
  void initState() {
    super.initState();
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

  // 逐字打字效果
  void _startTyping() {
    if (!mounted || _page1Done) return;
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
        _scheduleNextLine();
      }
    });
  }

  // 一句打完後的停頓。用 Timer（而非 Future.delayed）才能被快轉取消。
  void _scheduleNextLine() {
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      _lineIndex++;
      _startTyping();
    });
  }

  // 點畫面快轉：整句還沒打完就先補完，已經打完則直接進下一句。
  // 舊版必須乾等約 6 秒才會出現「繼續」，對再次安裝或看過一次的人是純等待。
  void _skipTyping() {
    if (_page1Done) return;
    _playOnboardingSfx(SfxCue.tap);
    final line = _lines[_lineIndex];
    if (_displayText != line) {
      _typingTimer?.cancel();
      setState(() => _displayText = line);
      _scheduleNextLine();
      return;
    }
    _typingTimer?.cancel();
    _lineIndex++;
    _startTyping();
  }

  void _nextPage({bool playSound = true}) {
    if (_pageMoving) return;
    if (playSound) _playOnboardingSfx(SfxCue.tap);
    unawaited(_ensureOnboardingBgm());
    // 換頁前先收起鍵盤，避免下一頁殘留鍵盤
    FocusScope.of(context).unfocus();
    if (_currentPage < _pages.length - 1) {
      unawaited(_goToPage(_currentPage + 1));
    }
  }

  Future<void> _goToPage(int page) async {
    setState(() {
      _pageMoving = true;
      _currentPage = page;
    });
    if (_reduceMotion) {
      _pageController.jumpToPage(page);
    } else {
      await _pageController.animateToPage(
        page,
        duration: AppMotion.settle,
        curve: AppMotion.curve,
      );
    }
    if (mounted) setState(() => _pageMoving = false);
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
      return UserValidators.heightCm(AppLocalizations.of(context), _heightCm());
    }
    return UserValidators.height(
      AppLocalizations.of(context),
      _heightController.text,
    );
  }

  String? get _weightErrTextRaw => UserValidators.weightIn(
    AppLocalizations.of(context),
    _weightController.text,
    _unit,
  );
  String? get _targetWeightErrTextRaw => UserValidators.targetWeightIn(
    AppLocalizations.of(context),
    _targetWeightController.text,
    _unit,
  );

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
    if (_bodyInfoSubmitAttempted && !_hasHeightInput) return _l10n.obNeedHeight;
    final raw = _heightErrTextRaw;
    if (raw != null) return raw;
    if (_bmiOddVisible) return _l10n.obRatioOdd;
    return null;
  }

  String? get _weightErrText {
    if (_weightFocus.hasFocus) return null;
    if (!_weightInputFinished) return null;
    if (_bodyInfoSubmitAttempted && _weightController.text.trim().isEmpty) {
      return _l10n.obNeedWeight;
    }
    final raw = _weightErrTextRaw;
    if (raw != null) return raw;
    if (_bmiOddVisible) return _l10n.obRatioOdd;
    return null;
  }

  String? get _targetWeightErrText {
    if (_targetWeightFocus.hasFocus) return null;
    if (!_targetWeightInputFinished) return null;
    return _targetWeightErrTextRaw;
  }

  // 性別/生日是非 TextField 控制項（chip / picker），用獨立 helper 顯示紅字
  String? get _genderError {
    if (_bodyInfoSubmitAttempted && _gender.isEmpty) return _l10n.obNeedGender;
    return null;
  }

  String? get _birthdayError {
    final raw = _birthdayController.text.trim();
    final shouldValidate =
        _bodyInfoSubmitAttempted ||
        _birthdayTouched ||
        !_birthdayFocus.hasFocus;
    if (_bodyInfoSubmitAttempted && raw.isEmpty) return _l10n.obNeedBirthday;
    if (raw.isEmpty || !shouldValidate) return null;

    final parsed = parseLenientDate(raw);
    if (parsed == null) return _l10n.obBirthdayUnparsed;
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
      return _l10n.obBirthdayOutOfRange;
    }
    return UserValidators.birthday(AppLocalizations.of(context), value);
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
      accent: AppPalette.brand,
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
          Icon(Icons.favorite_outline, size: 14, color: AppPalette.brand),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              _l10n.obHealthyWeightRange(
                '${suggestion.low}',
                '${suggestion.high}',
                suggestion.unit,
              ),
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
          foregroundColor: AppPalette.brand,
          backgroundColor: AppSurfaces.fill,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppSurfaces.divider),
          ),
        ),
        child: Text(
          _l10n.obSuggestTarget('${suggestion.suggest}', suggestion.unit),
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
    if (UserValidators.birthday(AppLocalizations.of(context), _birthday) !=
        null) {
      return false;
    }
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
    if (_pageMoving) return;
    _playOnboardingSfx(SfxCue.cancel);
    // 換頁前先收起鍵盤，與 _nextPage 一致
    FocusScope.of(context).unfocus();
    final page = _pages[_currentPage];
    if (page.inSubStep()) {
      setState(page.exitSubStep);
      return;
    }
    if (_currentPage > 0) {
      unawaited(_goToPage(_currentPage - 1));
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

  // 所有步驟使用相同的閱讀順序：介面標題 → 兔咪／示意 → 對話 → 內容。
  // 主操作屬於外層 footer，因此不會隨長表單或鍵盤捲走。
  Widget _speechBubble(String text, {double fontSize = 16}) {
    return Container(
      key: const ValueKey('onboarding-speech'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppSurfaces.card,
        borderRadius: BorderRadius.circular(AppCardStyle.radius),
        border: Border.all(color: AppPalette.brand.withValues(alpha: 0.16)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppInk.strong,
          fontSize: fontSize,
          height: 1.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _mascot({double size = 80, String emotion = 'neutral_front'}) {
    final asset = MascotEmotion.values
        .firstWhere(
          (e) => e.assetKey == emotion,
          orElse: () => MascotEmotion.neutralFront,
        )
        .assetPath;
    return SizedBox.square(
      dimension: size,
      child: FittedBox(
        child: MascotStage(
          asset: asset,
          accent: AppPalette.brand,
          reactionTick: 0,
          reduceMotion: _reduceMotion,
          paused: _reduceMotion,
          onTap: () => _playOnboardingSfx(SfxCue.tap),
        ),
      ),
    );
  }

  Widget _mascotPage({
    required String title,
    String? subtitle,
    required String emotion,
    required Widget content,
    ScrollController? scrollController,
    bool welcome = false,
    bool form = false,
    Widget? featurePreview,
    VoidCallback? onTapBackground,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
        final compact = constraints.maxHeight < 480;
        return GestureDetector(
          onTap: () {
            FocusScope.of(context).unfocus();
            onTapBackground?.call();
          },
          behavior: HitTestBehavior.opaque,
          child: SingleChildScrollView(
            key: ValueKey('onboarding-scroll-$title'),
            controller: scrollController,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      key: const ValueKey('onboarding-step-title'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: welcome ? 27 : 23,
                        fontWeight: FontWeight.w900,
                        height: 1.25,
                        color: AppInk.strong,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppInk.soft,
                          height: 1.5,
                          fontSize: 14,
                        ),
                      ),
                    ],
                    if (!keyboard) ...[
                      const SizedBox(height: 18),
                      if (form)
                        Center(child: _mascot(size: 100, emotion: emotion))
                      else
                        _gardenArtwork(
                          emotion: emotion,
                          welcome: welcome,
                          compact: compact,
                          featurePreview: featurePreview,
                        ),
                    ],
                    const SizedBox(height: 18),
                    content,
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // 沿用核准的花園背景與兔咪 PNG。花園只作有限大小的相遇舞台，
  // 不把高亮背景鋪在整張表單下；每一步的文字都有自己的奶油卡面。
  Widget _gardenArtwork({
    required String emotion,
    required bool welcome,
    required bool compact,
    Widget? featurePreview,
  }) {
    final height = welcome ? (compact ? 190.0 : 244.0) : 164.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(36),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/scenes/onboarding/onboarding_bg_v3.png',
              fit: BoxFit.cover,
              alignment: Alignment.bottomCenter,
              excludeFromSemantics: true,
            ),
            if (featurePreview == null)
              Center(
                child: _mascot(size: height - 12, emotion: emotion),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _mascot(size: 142, emotion: emotion),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(flex: 6, child: featurePreview),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _previewCard(Color accent, List<Widget> children) {
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppSurfaces.card.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: accent.withValues(alpha: 0.18)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }

  Widget _waterPreview() => _previewCard(AppPalette.water, [
    Icon(Icons.local_drink_rounded, size: 42, color: AppPalette.water),
    const SizedBox(height: 12),
    Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        4,
        (i) => Icon(
          i < 2 ? Icons.water_drop_rounded : Icons.water_drop_outlined,
          size: 20,
          color: AppPalette.water.withValues(alpha: i < 2 ? 1 : 0.4),
        ),
      ),
    ),
  ]);

  Widget _focusPreview() => _previewCard(AppPalette.focus, [
    SizedBox.square(
      dimension: 80,
      child: CustomPaint(
        painter: const TimerRingPainter(
          progress: 0.72,
          color: AppPalette.focus,
        ),
        child: const Center(
          child: Icon(
            Icons.menu_book_rounded,
            size: 32,
            color: AppPalette.focus,
          ),
        ),
      ),
    ),
  ]);

  Widget _familyPreview() => _previewCard(AppPalette.family, [
    Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.favorite_rounded, size: 24, color: AppPalette.family),
        const SizedBox(width: 6),
        Icon(Icons.star_rounded, size: 20, color: AppPalette.habit),
      ],
    ),
    const SizedBox(height: 12),
    for (var i = 0; i < 2; i++)
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Icon(
              i == 0 ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 19,
              color: AppPalette.family,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 7,
                decoration: BoxDecoration(
                  color: AppPalette.family.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ),
      ),
  ]);

  Widget _buildPage1() {
    final emotion = _page1Done
        ? 'smile'
        : (_lineIndex == 0
              ? 'wake'
              : (_lineIndex == 1 ? 'neutral_front' : 'smile'));
    return _mascotPage(
      title: _l10n.obWelcomeTitle,
      subtitle: _l10n.obWelcomeSubtitle,
      emotion: emotion,
      welcome: true,
      onTapBackground: _skipTyping,
      content: _speechBubble(_displayText, fontSize: 17),
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
    return IconButton.filledTonal(
      key: const ValueKey('onboarding-name-dice'),
      onPressed: _rollMascotName,
      style: IconButton.styleFrom(
        minimumSize: const Size(56, 56),
        backgroundColor: AppPalette.brand.withValues(alpha: 0.12),
        foregroundColor: AppPalette.brand,
      ),
      icon: const Icon(Icons.casino_rounded, size: 26),
    );
  }

  Widget _buildPage2() => _mascotPage(
    title: _l10n.obMeetTitle,
    emotion: 'smile',
    content: Column(
      children: [
        _speechBubble('對了...\n你可以幫我取個名字。\n想不到的話，按旁邊骰子幫我抽一個。'),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _namedField(
                controller: _mascotController,
                label: _l10n.obNameHint,
                keyName: 'onboarding-mascot-name',
                formatters: const [
                  DisplayWidthLimitingFormatter(kMascotNameMaxUnits),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _diceButton(),
          ],
        ),
      ],
    ),
  );

  Widget _namedField({
    required TextEditingController controller,
    required String label,
    required String keyName,
    List<TextInputFormatter>? formatters,
    int? maxLength,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(color: AppInk.soft, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      TextField(
        key: ValueKey(keyName),
        controller: controller,
        inputFormatters: formatters,
        maxLength: maxLength,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => FocusScope.of(context).unfocus(),
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppInk.strong,
        ),
        decoration: InputDecoration(
          counterText: '',
          fillColor: AppSurfaces.card,
        ),
      ),
    ],
  );

  Widget _buildPage3() => _mascotPage(
    title: _l10n.obMeetTitle,
    emotion: 'expect',
    content: Column(
      children: [
        _speechBubble('那...你呢？\n$_mascotName 以後要怎麼叫你？'),
        const SizedBox(height: 20),
        _namedField(
          controller: _nicknameController,
          label: _l10n.obNicknameHint,
          keyName: 'onboarding-nickname',
          maxLength: 12,
        ),
      ],
    ),
  );

  Widget _featureIntroPage({
    required String title,
    required String bubble,
    required Widget preview,
  }) => _mascotPage(
    title: title,
    emotion: 'neutral_front',
    featurePreview: preview,
    content: Column(
      children: [
        _speechBubble(bubble),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.tune_rounded, size: 18, color: AppInk.soft),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _l10n.obConfirmOffMessage,
                style: const TextStyle(
                  color: AppInk.soft,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  // 按「不用了」跳確認框：確定才關閉（之後仍能在設定再開）。
  Future<void> _confirmDecline(String name, VoidCallback onConfirmed) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(_l10n.obConfirmOffTitle(name)),
        content: Text(_l10n.obConfirmOffMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_l10n.obKeepIt),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppInk.danger),
            child: Text(_l10n.obTurnOff),
          ),
        ],
      ),
    );
    if (ok == true) {
      _playOnboardingSfx(SfxCue.cancel);
      onConfirmed();
    }
  }

  Widget _buildPage4() => _featureIntroPage(
    title: _l10n.obWaterFeature,
    bubble: '口渴前，我會輕輕提醒你喝水。\n先幫你開著好嗎？',
    preview: _waterPreview(),
  );

  Widget _buildPage5() => _featureIntroPage(
    title: _l10n.obFocusFeature,
    bubble: '專心的時候，我幫你顧著時間。\n要先開著專注計時嗎？',
    preview: _focusPreview(),
  );

  Widget _buildFamilyPage() => _featureIntroPage(
    title: _l10n.obFamilyFeature,
    bubble: '家裡有小朋友的話，\n我也能陪他們記小任務。\n要先開著嗎？',
    preview: _familyPreview(),
  );

  Widget _buildHabitPickerPage() => _mascotPage(
    title: _l10n.obHabitsTitle,
    emotion: 'smile',
    form: true,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _speechBubble('要不要先放幾個小習慣？\n之後都可以再改。'),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final h in _kOnboardingHabits)
                  SizedBox(
                    width: width,
                    child: _habitChip(h.name, h.emoji, h.freq),
                  ),
              ],
            );
          },
        ),
        _freqSection(),
      ],
    ),
  );

  Widget _freqSection() {
    final rows = _kOnboardingHabits
        .where((h) => h.freq && _selectedHabits.contains(h.name))
        .toList();
    final content = rows.isEmpty
        ? const SizedBox.shrink()
        : Container(
            key: const ValueKey('freq-panel'),
            margin: const EdgeInsets.only(top: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppSurfaces.card,
              borderRadius: BorderRadius.circular(AppCardStyle.radius),
              border: Border.all(color: AppSurfaces.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _l10n.obHabitFreqTitle,
                  style: const TextStyle(
                    color: AppInk.strong,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                for (final row in rows) ...[
                  const SizedBox(height: 18),
                  _freqRow(row.emoji, row.name),
                ],
              ],
            ),
          );
    if (_reduceMotion) return content;
    return AnimatedSize(
      duration: AppMotion.settle,
      alignment: Alignment.topCenter,
      child: content,
    );
  }

  Widget _freqRow(String emoji, String name) {
    final times = _weeklyTimes[name];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$emoji $name',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (times != null)
              _weeklyStepper(name, times)
            else
              _choicePill(_l10n.hsWeekly, false, () {
                _playOnboardingSfx(SfxCue.tap);
                setState(() => _weeklyTimes[name] = 3);
              }, key: ValueKey('weekly-pill-$name')),
            _choicePill(_l10n.hsDaily, times == null, () {
              if (times != null) _playOnboardingSfx(SfxCue.tap);
              setState(() => _weeklyTimes.remove(name));
            }),
          ],
        ),
      ],
    );
  }

  Widget _weeklyStepper(String name, int times) => Container(
    key: ValueKey('weekly-stepper-$name'),
    padding: const EdgeInsets.symmetric(horizontal: 4),
    decoration: BoxDecoration(
      color: AppPalette.brand,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            _l10n.hsWeekly,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        _stepBtn(Icons.remove_rounded, () {
          _playOnboardingSfx(SfxCue.tap);
          setState(() => _weeklyTimes[name] = (times - 1).clamp(1, 7));
        }),
        Text(
          _l10n.obTimesPerWeek(times),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        _stepBtn(Icons.add_rounded, () {
          _playOnboardingSfx(SfxCue.tap);
          setState(() => _weeklyTimes[name] = (times + 1).clamp(1, 7));
        }),
      ],
    ),
  );

  Widget _stepBtn(IconData icon, VoidCallback onTap) => IconButton(
    onPressed: onTap,
    style: IconButton.styleFrom(
      minimumSize: const Size(44, 44),
      foregroundColor: Colors.white,
    ),
    icon: Icon(icon, size: 20),
  );

  Widget _choicePill(
    String label,
    bool selected,
    VoidCallback onTap, {
    Key? key,
  }) => AppPressable(
    key: key,
    selected: selected,
    borderRadius: 18,
    onPressed: onTap,
    child: AnimatedContainer(
      duration: AppMotion.duration(context, AppMotion.quick),
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? AppPalette.brand : AppSurfaces.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? AppPalette.brand : AppSurfaces.divider,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : AppInk.strong,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );

  Widget _habitChip(String name, String emoji, bool freq) {
    final selected = _selectedHabits.contains(name);
    return AppPressable(
      key: ValueKey('onboarding-habit-$name'),
      selected: selected,
      onPressed: () {
        _playOnboardingSfx(SfxCue.tap);
        setState(() {
          if (selected) {
            _selectedHabits.remove(name);
            _weeklyTimes.remove(name);
          } else {
            _selectedHabits.add(name);
            if (freq) _weeklyTimes[name] = 3;
          }
        });
      },
      child: AnimatedContainer(
        duration: AppMotion.duration(context, AppMotion.quick),
        constraints: const BoxConstraints(minHeight: 98),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppPalette.brand.withValues(alpha: 0.12)
              : AppSurfaces.card,
          borderRadius: BorderRadius.circular(AppCardStyle.radius),
          border: Border.all(
            color: selected ? AppPalette.brand : AppSurfaces.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 24)),
                const Spacer(),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 20,
                  color: selected ? AppPalette.brand : AppInk.iconFaint,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              name,
              style: const TextStyle(
                color: AppInk.strong,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // onboarding 用的單欄數字輸入（橘色風格）
  // iOS 純數字鍵盤沒有「完成」鍵，但因為鍵盤彈出時 _mascotPage 會
  // 把整層內容往上推（兔咪暫時被擠到畫面外），下方的「填寫完成 / 下次
  // 再說」按鈕都能點到，所以不再額外塞 suffix icon
  Widget _onboardingNumField({
    required String fieldId,
    required TextEditingController controller,
    required String label,
    String? errorText,
    Widget? suffixWidget,
    FocusNode? focusNode,
    // 非 null 時掛上自動補小數（只在公制欄位傳，傳該欄位的公制合理上限）
    num? decimalMax,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppInk.soft,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: ValueKey('onboarding-$fieldId'),
          controller: controller,
          focusNode: focusNode,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            if (decimalMax != null)
              bodyMetricFormatter(decimalMax)
            else
              maxValueFormatter(999),
          ],
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            errorText: errorText,
            errorMaxLines: 3,
            fillColor: AppSurfaces.card,
          ),
        ),
        if (suffixWidget != null)
          Align(alignment: Alignment.centerLeft, child: suffixWidget),
      ],
    );
  }

  // imperial 模式的 ft/in 兩欄並排
  Widget _onboardingFtInRow() {
    InputDecoration deco(String label, String suffix) => InputDecoration(
      labelText: label,
      suffixText: suffix,
      filled: true,
      fillColor: AppSurfaces.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppSurfaces.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppPalette.brand),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('onboarding-height'),
                controller: _heightController,
                focusNode: _heightFocus,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                decoration: deco(_l10n.obHeightFt, 'ft'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                key: const ValueKey('onboarding-height-inches'),
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
              style: TextStyle(color: AppInk.danger, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _buildPage6() {
    final bmiOdd = _bmiOddOnboarding;
    final emotion = bmiOdd ? 'sad' : 'smile';
    final bubbleText = bmiOdd ? '嗯…身高或體重好像需要再確認一下。' : '我可以幫你紀錄身高、體重喔！';

    return _mascotPage(
      title: _l10n.obBodyTitle,
      subtitle: _l10n.obBodySubtitle,
      emotion: emotion,
      form: true,
      scrollController: _bodyInfoScrollCtrl,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _speechBubble(bubbleText),
          const SizedBox(height: 14),
          // 性別選擇。三顆 chip 走 Wrap：中文（男／女／不透露）在 SE 上一行
          // 放得下，版面不變；英文（Prefer not to say）會自動折到第二行，
          // 原本的固定 Row 在 SE 上會溢出 30px。
          Row(
            children: [
              Text(
                _l10n.genderLabel,
                style: TextStyle(
                  color: AppPalette.brand,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _genderChip('男', _l10n.genderMale),
                    _genderChip('女', _l10n.genderFemale),
                    _genderChip('不透露', _l10n.genderUndisclosed),
                  ],
                ),
              ),
            ],
          ),
          if (_genderError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                _genderError!,
                style: TextStyle(color: AppInk.danger, fontSize: 12),
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
              fieldId: 'height',
              controller: _heightController,
              focusNode: _heightFocus,
              label: _l10n.obHeightCm,
              errorText: _heightErrText,
              decimalMax: UserRanges.heightMaxCm,
            ),
          const SizedBox(height: 10),
          // 體重
          _onboardingNumField(
            fieldId: 'weight',
            controller: _weightController,
            focusNode: _weightFocus,
            label: _l10n.obWeightWithUnit(UnitFormat.weightLabel(_unit)),
            errorText: _weightErrText,
            // 英制(lb)不補小數
            decimalMax: _unit == UnitSystem.imperial
                ? null
                : UserRanges.weightMaxKg,
          ),
          const SizedBox(height: 10),
          // 目標體重（選填）
          _onboardingNumField(
            fieldId: 'target-weight',
            controller: _targetWeightController,
            focusNode: _targetWeightFocus,
            label: _l10n.obTargetWeightOptional(UnitFormat.weightLabel(_unit)),
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
            key: const ValueKey('onboarding-birthday'),
            controller: _birthdayController,
            focusNode: _birthdayFocus,
            readOnly: true,
            showCursor: false,
            onTap: _openBirthdayPicker,
            decoration: InputDecoration(
              labelText: _l10n.birthdayLabel,
              hintText: _l10n.obBirthdayHint,
              errorText: _birthdayError,
              errorMaxLines: 2,
              suffixIcon: const Icon(
                Icons.calendar_today_outlined,
                size: 18,
                color: AppPalette.brand,
              ),
              filled: true,
              fillColor: AppSurfaces.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppSurfaces.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppPalette.brand),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 選項的 value 維持既有中文存值；顯示文字才走 l10n。
  Widget _genderChip(String value, String label) =>
      _choicePill(label, _gender == value, () {
        if (_gender != value) _playOnboardingSfx(SfxCue.tap);
        setState(() => _gender = value);
      });

  Widget _activityChip(String value) =>
      _choicePill(_activityLabel(value), _activityLevel == value, () {
        if (_activityLevel != value) _playOnboardingSfx(SfxCue.tap);
        setState(() => _activityLevel = value);
      });

  // 活動量選擇區：用「一週運動幾天」取代抽象的輕度/中度。
  Widget _onboardingActivitySelector() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppSurfaces.fill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.brand.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _l10n.obActivityTitle,
            style: TextStyle(
              color: AppPalette.brand,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: _activityLevels.map(_activityChip).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPage7() => _mascotPage(
    title: _l10n.obReadyTitle,
    emotion: 'pop_happy',
    welcome: true,
    content: Column(
      children: [
        _speechBubble('好了，$_nickname。\n以後也一起慢慢來。', fontSize: 17),
        const SizedBox(height: 20),
        if (_waterEnabled == true ||
            _timerEnabled == true ||
            _familyEnabled == true ||
            _selectedHabits.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppSurfaces.card,
              borderRadius: BorderRadius.circular(AppCardStyle.radius),
              border: Border.all(color: AppSurfaces.divider),
            ),
            child: Column(
              children: [
                if (_waterEnabled == true)
                  _readyRow(
                    Icons.water_drop_rounded,
                    _l10n.obWaterFeature,
                    AppPalette.water,
                  ),
                if (_timerEnabled == true)
                  _readyRow(
                    Icons.timer_rounded,
                    _l10n.obFocusFeature,
                    AppPalette.focus,
                  ),
                if (_familyEnabled == true)
                  _readyRow(
                    Icons.favorite_rounded,
                    _l10n.obFamilyFeature,
                    AppPalette.family,
                  ),
                if (_selectedHabits.isNotEmpty)
                  _readyRow(
                    Icons.check_circle_rounded,
                    _l10n.hsPickedPresets(_selectedHabits.length),
                    AppPalette.habit,
                  ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _readyRow(IconData icon, String label, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppInk.strong,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Icon(Icons.check_rounded, size: 18, color: AppPalette.success),
      ],
    ),
  );

  String get _primaryLabel => switch (_currentPage) {
    0 => _page1Done ? _l10n.obContinue : _l10n.obTapToContinue,
    3 => _l10n.obWaterAccept,
    4 || 5 => _l10n.obFocusAccept,
    6 => _selectedHabits.isEmpty ? _l10n.commonSkip : _l10n.obNext,
    7 => _l10n.obFillDone,
    8 => _l10n.obStart,
    _ => _l10n.obNext,
  };

  void _primaryAction() {
    switch (_currentPage) {
      case 0:
        if (_page1Done) {
          _nextPage();
        } else {
          _skipTyping();
        }
      case 1:
        setState(
          () => _mascotName = _mascotController.text.trim().isEmpty
              ? _l10n.mascotDefaultName
              : _mascotController.text.trim(),
        );
        _nextPage();
      case 2:
        if (_nicknameController.text.trim().isEmpty) return;
        setState(() => _nickname = _nicknameController.text.trim());
        _nextPage();
      case 3:
        setState(() => _waterEnabled = true);
        _nextPage();
      case 4:
        setState(() => _timerEnabled = true);
        _nextPage();
      case 5:
        setState(() => _familyEnabled = true);
        _nextPage();
      case 7:
        _tryFinishBodyInfo();
      case 8:
        unawaited(_finish());
      default:
        _nextPage();
    }
  }

  void _declineCurrentFeature() {
    final page = _currentPage;
    final name = switch (page) {
      3 => _l10n.obWaterFeature,
      4 => _l10n.obFocusFeature,
      _ => _l10n.obFamilyFeature,
    };
    _playOnboardingSfx(SfxCue.tap);
    unawaited(
      _confirmDecline(name, () {
        setState(() {
          if (page == 3) _waterEnabled = false;
          if (page == 4) _timerEnabled = false;
          if (page == 5) _familyEnabled = false;
        });
        _nextPage(playSound: false);
      }),
    );
  }

  Widget _footer() {
    final isFeature = _currentPage >= 3 && _currentPage <= 5;
    final enabled =
        !_pageMoving &&
        (_currentPage != 2 || _nicknameController.text.trim().isNotEmpty);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppSurfaces.canvas,
        border: Border(
          top: BorderSide(color: AppSurfaces.divider.withValues(alpha: 0.65)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('onboarding-primary'),
                    onPressed: enabled ? _primaryAction : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppPalette.brand,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(48, 56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 24),
                        Expanded(
                          child: Text(
                            _primaryLabel,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          _currentPage == 8
                              ? Icons.favorite_rounded
                              : Icons.arrow_forward_rounded,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
                if (isFeature || _currentPage == 7)
                  TextButton(
                    key: const ValueKey('onboarding-secondary'),
                    onPressed: _pageMoving
                        ? null
                        : (isFeature ? _declineCurrentFeature : _nextPage),
                    style: TextButton.styleFrom(
                      foregroundColor: AppInk.soft,
                      minimumSize: const Size(44, 44),
                    ),
                    child: Text(
                      isFeature ? _l10n.obDecline : _l10n.obLaterMaybe,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox.square(
                dimension: 48,
                child: _currentPage > 0
                    ? IconButton(
                        key: const ValueKey('onboarding-back'),
                        tooltip: _l10n.obBack,
                        onPressed: _pageMoving ? null : _handleBack,
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: AppInk.strong,
                        ),
                      )
                    : Icon(
                        Icons.favorite_rounded,
                        color: AppPalette.brand,
                        size: 22,
                      ),
              ),
              Expanded(
                child: Text(
                  _l10n.appTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppInk.strong,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              AudioControlButton(
                style: AudioControlStyle.onboarding,
                accent: AppPalette.brand,
                onMusicEnabled: () =>
                    unawaited(_ensureOnboardingBgm(unmute: true)),
              ),
            ],
          ),
          if (!keyboard) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: List.generate(
                        _pages.length,
                        (i) => Expanded(
                          child: AnimatedContainer(
                            duration: AppMotion.duration(
                              context,
                              AppMotion.quick,
                            ),
                            height: 7,
                            margin: const EdgeInsets.only(right: 5),
                            decoration: BoxDecoration(
                              color: i <= _currentPage
                                  ? AppPalette.brand
                                  : AppSurfaces.divider,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${_currentPage + 1} / ${_pages.length}',
                    key: const ValueKey('onboarding-step-counter'),
                    style: AppType.digits(fontSize: 14, color: AppInk.soft),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.dark,
    child: Scaffold(
      backgroundColor: AppSurfaces.canvas,
      // 整個 Column 在 Scaffold 的鍵盤避讓區內；footer 真正停在鍵盤上緣，
      // 320 × 667 + 300 pt 鍵盤時，上方只保留 60 pt header，內容仍可捲讀。
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: PageView.builder(
                key: const ValueKey('onboarding-pages'),
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _pages.length,
                itemBuilder: (context, index) => TickerMode(
                  enabled: index == _currentPage,
                  child: _pages[index].build(),
                ),
              ),
            ),
            _footer(),
          ],
        ),
      ),
    ),
  );
}
