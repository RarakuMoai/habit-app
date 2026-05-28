import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '../utils/bgm_service.dart';
import '../utils/mascot.dart';
import '../utils/units.dart';
import '../utils/user_validators.dart';

// 引導頁「習慣選擇」清單（喝水交由畫面4處理，故不列入）
// freq=true：適合「每週幾次」的習慣，選取後會出現每日/每週切換
const List<({String emoji, String name, bool freq})> _kOnboardingHabits = [
  (emoji: '🦷', name: '刷牙', freq: false),
  (emoji: '🧹', name: '整理環境', freq: false),
  (emoji: '📖', name: '閱讀', freq: true),
  (emoji: '🌅', name: '早起', freq: false),
  (emoji: '🏃', name: '運動', freq: true),
  (emoji: '🧘', name: '冥想', freq: true),
  (emoji: '🌙', name: '早睡', freq: false),
];

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // 畫面1：打字動畫
  final List<String> _lines = ['嗯...你來了。', '我是兔咪，平常有點愛睡。', '但你開始的時候，我會醒來陪你。'];
  int _lineIndex = 0;
  String _displayText = '';
  bool _page1Done = false;
  Timer? _typingTimer;

  // 畫面2：吉祥物名稱
  final TextEditingController _mascotController = TextEditingController(
    text: '兔咪',
  );

  // 畫面3：用戶暱稱
  final TextEditingController _nicknameController = TextEditingController();
  String _mascotName = '兔咪';

  // 畫面4：喝水
  int _waterStep = 0; // 0=初始選項, 1=追問
  String _waterFollowup = '';
  bool? _waterEnabled;

  // 畫面5：番茄鐘
  int _timerStep = 0; // 0=初始選項, 1=追問, 2=直接完成
  String _timerFollowup = '';
  bool? _timerEnabled;

  // 畫面6（新）：家庭功能引導
  int _familyStep = 0; // 0=初始, 1=追問(有小孩), 2=安慰語
  bool? _familyEnabled;

  // 畫面7：身體資訊
  String _gender = '';
  // 身高（metric: cm；imperial: ft + 額外的 _heightInController 是 in）
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _heightInController = TextEditingController();
  // 體重 / 目標體重（依當下單位是 kg 或 lb）
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _targetWeightController = TextEditingController();
  UnitSystem _unit = UnitSystem.metric;
  DateTime? _birthday; // 生日（選填）

  // 用戶暱稱（畫面3填完後存起來）
  String _nickname = '';

  // 習慣選擇頁：使用者勾選的習慣名稱
  final Set<String> _selectedHabits = {};
  // 習慣選擇頁：設為「每週」的習慣 → 名稱對應每週次數；未列入者為每日
  final Map<String, int> _weeklyTimes = {};

  @override
  void initState() {
    super.initState();
    _nicknameController.addListener(() => setState(() {}));
    _heightController.addListener(() => setState(() {}));
    _heightInController.addListener(() => setState(() {}));
    _weightController.addListener(() => setState(() {}));
    _targetWeightController.addListener(() => setState(() {}));
    _loadUnit();
    // 等第一幀渲染完成（Offstage 預熱字形後）再啟動打字動畫
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startTyping();
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
    super.dispose();
  }

  // 逐字打字效果
  void _startTyping() {
    if (!mounted) return;
    if (_lineIndex >= _lines.length) {
      setState(() => _page1Done = true);
      return;
    }
    final chars = _lines[_lineIndex].characters.toList(); // 預先拆好，避免每次重建
    int charIndex = 0;
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

  void _nextPage() {
    // 換頁前先收起鍵盤，避免下一頁殘留鍵盤
    FocusScope.of(context).unfocus();
    if (_currentPage < 8) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
      setState(() => _currentPage++);
    }
  }

  // 身高/體重欄位格式化：最多 3 位整數 + 1 位小數，且輸入超過上限時自動壓回上限
  TextInputFormatter _maxValueFormatter(int max) {
    final pattern = RegExp(r'^\d{0,3}(\.\d?)?$');
    return TextInputFormatter.withFunction((oldValue, newValue) {
      final text = newValue.text;
      if (text.isEmpty) return newValue;
      // 格式不符（多個小數點、超過 1 位小數、整數超過 3 位）→ 維持原值
      if (!pattern.hasMatch(text)) return oldValue;
      // 數值超過上限 → 壓回上限
      final v = double.tryParse(text);
      if (v != null && v > max) {
        final t = max.toString();
        return TextEditingValue(
          text: t,
          selection: TextSelection.collapsed(offset: t.length),
        );
      }
      return newValue;
    });
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

  // 目前單位下顯示用的範圍錯誤
  String? get _heightErrText {
    if (_unit == UnitSystem.imperial) {
      if (_heightController.text.trim().isEmpty &&
          _heightInController.text.trim().isEmpty) {
        return null;
      }
      return UserValidators.heightCm(_heightCm());
    }
    return UserValidators.height(_heightController.text);
  }

  String? get _weightErrText =>
      UserValidators.weightIn(_weightController.text, _unit);
  String? get _targetWeightErrText =>
      UserValidators.targetWeightIn(_targetWeightController.text, _unit);

  // 目標體重建議：依身高的健康 BMI 範圍（18.5–24），建議值取 BMI 22
  Widget _targetWeightHint() {
    final cm = _heightCm();
    if (cm == null || cm < 1 || cm > 999) return const SizedBox.shrink();
    final hM = cm / 100;
    final lowKg = (18.5 * hM * hM).round();
    final highKg = (24 * hM * hM).round();
    final suggestKg = (22 * hM * hM).round();
    final lowDisp = _unit == UnitSystem.imperial
        ? UnitConvert.kgToLb(lowKg.toDouble()).round()
        : lowKg;
    final highDisp = _unit == UnitSystem.imperial
        ? UnitConvert.kgToLb(highKg.toDouble()).round()
        : highKg;
    final suggestDisp = _unit == UnitSystem.imperial
        ? UnitConvert.kgToLb(suggestKg.toDouble()).round()
        : suggestKg;
    final unitLabel = UnitFormat.weightLabel(_unit);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(Icons.favorite_outline, size: 14, color: Colors.orange.shade400),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              '健康體重約 $lowDisp–$highDisp $unitLabel',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          GestureDetector(
            onTap: () => setState(
              () => _targetWeightController.text = suggestDisp.toString(),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Text(
                '建議 $suggestDisp $unitLabel',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.orange.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
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
    if (_heightErrText != null) return false;
    if (_weightErrText != null) return false;
    if (_targetWeightErrText != null) return false;
    if (UserValidators.birthday(_birthday) != null) return false;
    // BMI 比例檢查（用公制換算）
    if (cm != null && kg != null && cm > 0) {
      final hM = cm / 100;
      final bmi = kg / (hM * hM);
      if (bmi < UserRanges.bmiMin || bmi > UserRanges.bmiMax) return false;
    }
    return true;
  }

  bool get _bmiOddOnboarding {
    final cm = _heightCm();
    final kg = _weightKgFromCtrl(_weightController);
    if (cm == null || kg == null || cm <= 0) return false;
    final hM = cm / 100;
    final bmi = kg / (hM * hM);
    return bmi < UserRanges.bmiMin || bmi > UserRanges.bmiMax;
  }

  // 回上一步：畫面4/5/6 若在追問子步驟，先退回初始選項；否則回上一畫面
  void _handleBack() {
    // 換頁前先收起鍵盤，與 _nextPage 一致
    FocusScope.of(context).unfocus();
    if (_currentPage == 3 && _waterStep == 1) {
      setState(() => _waterStep = 0);
      return;
    }
    if (_currentPage == 4 && _timerStep == 1) {
      setState(() => _timerStep = 0);
      return;
    }
    if (_currentPage == 5 && _familyStep > 0) {
      setState(() => _familyStep = 0);
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    await prefs.setString(
      'mascot_name',
      _mascotController.text.trim().isEmpty
          ? '兔咪'
          : _mascotController.text.trim(),
    );
    await prefs.setString(
      'user_nickname',
      _nicknameController.text.trim().isEmpty
          ? '你'
          : _nicknameController.text.trim(),
    );
    await prefs.setBool('water_enabled', _waterEnabled ?? false);
    await prefs.setBool('timer_enabled', _timerEnabled ?? false);
    await prefs.setBool('family_enabled', _familyEnabled ?? false);

    // 身體資訊
    if (_gender.isNotEmpty) await prefs.setString('user_gender', _gender);
    final heightCm = _heightCm();
    if (heightCm != null &&
        heightCm >= UserRanges.heightMinCm &&
        heightCm <= UserRanges.heightMaxCm) {
      await prefs.setDouble('user_height', heightCm);
    }
    final weightKg = _weightKgFromCtrl(_weightController);
    if (weightKg != null &&
        weightKg >= UserRanges.weightMinKg &&
        weightKg <= UserRanges.weightMaxKg) {
      await prefs.setDouble('user_weight', weightKg);
      await prefs.setBool('weight_tracking_enabled', true);
      // 自動新增體重紀錄習慣
      await _addWeightHabit(prefs);
    }
    final targetKg = _weightKgFromCtrl(_targetWeightController);
    if (targetKg != null &&
        targetKg >= UserRanges.targetWeightMinKg &&
        targetKg <= UserRanges.targetWeightMaxKg) {
      await prefs.setDouble('target_weight', targetKg);
    }
    // 選了喝水功能 → 自動加入「喝足夠的水」習慣
    if (_waterEnabled == true) _selectedHabits.add('喝足夠的水');
    // 引導頁「習慣選擇頁」勾選的習慣
    await _addPickedHabits(prefs);

    // 生日（選填），以 yyyy-MM-dd 格式儲存
    if (_birthday != null) {
      final b = _birthday!;
      await prefs.setString(
        'user_birthday',
        '${b.year.toString().padLeft(4, '0')}-'
            '${b.month.toString().padLeft(2, '0')}-'
            '${b.day.toString().padLeft(2, '0')}',
      );
    }

    if (!mounted) return;
    // 切換 BGM 到主 app 曲目（cross-fade）
    BgmService.instance.play('sounds/bgm_main.m4a');
    Navigator.of(context).pushReplacementNamed('/home');
  }

  // 在習慣清單自動新增體重紀錄
  Future<void> _addWeightHabit(SharedPreferences prefs) async {
    final String? habitsJson = prefs.getString('habits');
    List<Map<String, dynamic>> habits = [];
    if (habitsJson != null) {
      final List<dynamic> decoded = jsonDecode(habitsJson);
      habits = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
    }
    // 避免重複新增
    final exists = habits.any((h) => h['name'] == '體重紀錄');
    if (!exists) {
      habits.add({'name': '體重紀錄', 'done': false});
      await prefs.setString('habits', jsonEncode(habits));
    }
  }

  // 將習慣選擇頁勾選的習慣寫入習慣清單
  Future<void> _addPickedHabits(SharedPreferences prefs) async {
    if (_selectedHabits.isEmpty) return;
    final String? habitsJson = prefs.getString('habits');
    List<Map<String, dynamic>> habits = [];
    if (habitsJson != null) {
      final List<dynamic> decoded = jsonDecode(habitsJson);
      habits = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
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
    await prefs.setString('habits', jsonEncode(habits));
  }

  // 通用對話氣泡樣式
  Widget _speechBubble(String text, {double fontSize = 16}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomRight: Radius.circular(20),
          bottomLeft: Radius.circular(4),
        ),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: fontSize, color: Colors.orange.shade900),
        textAlign: TextAlign.center,
      ),
    );
  }

  // 吉祥物頭像（PNG，依情境切換情緒）
  Widget _mascot({double size = 80, String emotion = 'neutral_front'}) {
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        // 只淡入、不縮放——避免兔咪在動畫中看起來忽大忽小
        transitionBuilder: (child, anim) =>
            FadeTransition(opacity: anim, child: child),
        child: Image.asset(
          // 透過 MascotEmotion 取，會自動走新 CG / 舊圖路由
          MascotEmotion.values
              .firstWhere(
                (e) => e.assetKey == emotion,
                orElse: () => MascotEmotion.neutralFront,
              )
              .assetPath,
          key: ValueKey(emotion),
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  // 選項按鈕
  Widget _optionButton(String label, VoidCallback onTap, {Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: (color ?? Colors.orange).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: (color ?? Colors.orange).withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: color ?? Colors.orange.shade800,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ── 畫面1：吉祥物甦醒 ──
  // 引導頁版型：兔咪固定在上方，內容在下方區域置中（可捲動）。
  // 兔咪位置不受內容多寡影響，換頁時保持一致。
  Widget _mascotPage({required String emotion, required Widget content}) {
    return GestureDetector(
      // 點空白處收起鍵盤
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _mascot(size: 200, emotion: emotion),
                  const SizedBox(height: 16),
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
    // 依打字進度切換情緒：第1句剛醒(sleep) → 自我介紹(neutral) → 陪伴宣告(smile)
    final wakeEmotion = _page1Done
        ? 'smile'
        : (_lineIndex == 0
              ? 'sleep'
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

  // ── 畫面2：幫吉祥物命名 ──
  Widget _buildPage2() {
    return _mascotPage(
      emotion: 'smile',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _speechBubble('對了，你可以幫我取個名字！'),
          const SizedBox(height: 32),
          TextField(
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
          _speechBubble('$_mascotName：那…你呢？\n我以後要怎麼叫你？'),
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
                disabledBackgroundColor: Colors.grey.shade300,
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

  // ── 畫面4：喝水功能引導 ──
  Widget _buildPage4() {
    return _mascotPage(
      emotion: 'neutral_front',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_waterStep == 0) ...[
            _speechBubble('$_nickname！好名字～\n對了，你平常有在注意喝水嗎？'),
            const SizedBox(height: 32),
            _optionButton('有，但常常忘記', () {
              setState(() {
                _waterStep = 1;
                _waterFollowup = '常常忘記很正常～\n讓我幫你記錄、提醒你喝水好嗎？💧';
              });
            }),
            _optionButton('有在注意', () {
              setState(() {
                _waterStep = 1;
                _waterFollowup = '哇，很棒！\n那我們一起記錄，看杯數增加更有成就感！💧';
              });
            }),
            _optionButton('沒特別想到', () {
              setState(() {
                _waterStep = 1;
                _waterFollowup = '那就從今天開始吧～\n要不要我幫你記錄每天喝幾杯水？💧';
              });
            }),
            // 已養成習慣、不需記錄 → 不追問，直接下一步
            _optionButton('我自己會注意，不用記錄', () {
              setState(() => _waterEnabled = false);
              _nextPage();
            }),
          ] else ...[
            _speechBubble(_waterFollowup),
            const SizedBox(height: 32),
            // 追問簡化為二選一
            _optionButton('好啊，幫我記！💧', () {
              setState(() => _waterEnabled = true);
              _nextPage();
            }, color: Colors.blue),
            _optionButton('不用，我自己來', () {
              setState(() => _waterEnabled = false);
              _nextPage();
            }),
          ],
        ],
      ),
    );
  }

  // ── 畫面5：番茄鐘功能引導 ──
  Widget _buildPage5() {
    return _mascotPage(
      emotion: 'neutral_front',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_timerStep == 0) ...[
            _speechBubble('你平常工作或唸書的時候，\n容易分心嗎？'),
            const SizedBox(height: 32),
            _optionButton('超容易！', () {
              setState(() {
                _timerStep = 1;
                _timerFollowup = '我有個秘密武器！\n要試試番茄鐘嗎？🍅';
              });
            }),
            _optionButton('還好', () {
              setState(() {
                _timerStep = 1;
                _timerFollowup = '有個番茄鐘可以讓你更穩定喔，\n要開啟嗎？';
              });
            }),
            _optionButton('我很專注', () {
              // 不追問，靜默設為 false 直接下一步
              setState(() => _timerEnabled = false);
              _nextPage();
            }),
          ] else ...[
            _speechBubble(_timerFollowup),
            const SizedBox(height: 32),
            // 追問簡化為二選一
            _optionButton('好啊，試試看！🍅', () {
              setState(() => _timerEnabled = true);
              _nextPage();
            }, color: Colors.red.shade400),
            _optionButton('不用了謝謝', () {
              setState(() => _timerEnabled = false);
              _nextPage();
            }),
          ],
        ],
      ),
    );
  }

  // ── 畫面6（新）：家庭功能引導 ──
  Widget _buildFamilyPage() {
    return _mascotPage(
      emotion: 'neutral_front',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_familyStep == 0) ...[
            _speechBubble('對了，家裡有小朋友嗎？🐣'),
            const SizedBox(height: 32),
            _optionButton('有！', () {
              setState(() => _familyStep = 1);
            }),
            _optionButton('沒有', () {
              setState(() => _familyEnabled = false);
              _nextPage();
            }),
            _optionButton('以後再說', () {
              setState(() => _familyEnabled = false);
              _nextPage();
            }),
          ] else ...[
            _speechBubble('可以用獎勵積分幫小朋友養成好習慣喔！\n要開啟家庭模式嗎？🏠'),
            const SizedBox(height: 32),
            _optionButton('好啊，聽起來不錯！', () {
              setState(() => _familyEnabled = true);
              _nextPage();
            }, color: Colors.green),
            _optionButton('不用了', () {
              setState(() => _familyEnabled = false);
              _nextPage();
            }),
          ],
        ],
      ),
    );
  }

  // ── 畫面7：身體資訊（可跳過）──
  // 結構：頂部兔咪+對話 + 可滾動欄位區 + 底部固定按鈕（避免下次再說被擠到 fold 下方）
  // 習慣選擇頁：勾選想養成的習慣，完成後寫入習慣清單
  Widget _buildHabitPickerPage() {
    return _mascotPage(
      emotion: 'smile',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _speechBubble('要不要先挑幾個習慣開始？\n之後都能再增減喔！'),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _kOnboardingHabits
                .map((h) => _habitChip(h.name, h.emoji, h.freq))
                .toList(),
          ),
          _freqSection(),
          const SizedBox(height: 32),
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

  // 已選取且適合頻率的習慣 → 顯示每日/每週切換
  Widget _freqSection() {
    final rows = _kOnboardingHabits
        .where((h) => h.freq && _selectedHabits.contains(h.name))
        .toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.repeat_rounded, size: 15, color: Colors.orange.shade700),
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
        ...rows.map((h) => _freqRow(h.emoji, h.name)),
      ],
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
          if (isWeekly)
            _weeklyStepper(name, times)
          else
            GestureDetector(
              onTap: () => setState(() => _weeklyTimes[name] = 3),
              child: _freqPill('每週', false),
            ),
          const SizedBox(width: 6),
          // 每日（次要，靠右）
          GestureDetector(
            onTap: () => setState(() => _weeklyTimes.remove(name)),
            child: _freqPill('每日', !isWeekly),
          ),
        ],
      ),
    );
  }

  // 每週次數調整器：−／＋ 改每週次數（1~7）
  Widget _weeklyStepper(String name, int times) {
    return Container(
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? Colors.orange : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? Colors.orange : Colors.grey.shade300,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: selected ? Colors.white : Colors.grey.shade600,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }

  // 習慣選擇 Chip（可多選）
  Widget _habitChip(String name, String emoji, bool freq) {
    final selected = _selectedHabits.contains(name);
    return GestureDetector(
      onTap: () => setState(() {
        if (selected) {
          _selectedHabits.remove(name);
          _weeklyTimes.remove(name);
        } else {
          _selectedHabits.add(name);
          // 適合頻率的習慣預設為每週 3 次
          if (freq) _weeklyTimes[name] = 3;
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.orange : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? Colors.orange : Colors.grey.shade300,
          ),
        ),
        child: Text(
          '$emoji $name',
          style: TextStyle(
            color: selected ? Colors.white : Colors.grey.shade700,
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // onboarding 用的單欄數字輸入（橘色風格）
  Widget _onboardingNumField({
    required TextEditingController controller,
    required String label,
    String? errorText,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [_maxValueFormatter(999)],
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
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
    final bubbleText = bmiOdd
        ? '咦？身高跟體重的比例…\n好像怪怪的，再確認一下？'
        : '想讓我更了解你嗎？\n如果你有減重或健康目標，\n可以告訴我身高體重～';

    return _mascotPage(
      emotion: emotion,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _speechBubble(bubbleText),
          const SizedBox(height: 6),
          Text(
            '不想說也完全沒關係！',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
          const SizedBox(height: 20),
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
          const SizedBox(height: 14),
          // 身高（依單位顯示一格或兩格）
          if (_unit == UnitSystem.imperial)
            _onboardingFtInRow()
          else
            _onboardingNumField(
              controller: _heightController,
              label: '身高（cm）',
              errorText: _heightErrText,
            ),
          const SizedBox(height: 10),
          // 體重
          _onboardingNumField(
            controller: _weightController,
            label: '體重（${UnitFormat.weightLabel(_unit)}）',
            errorText: _weightErrText,
          ),
          const SizedBox(height: 10),
          // 目標體重（選填）
          _onboardingNumField(
            controller: _targetWeightController,
            label: '目標體重（${UnitFormat.weightLabel(_unit)}，選填）',
            errorText: _targetWeightErrText,
          ),
          _targetWeightHint(),
          const SizedBox(height: 10),
          // 生日（選填，點擊開啟日期選擇器）
          InkWell(
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: _birthday ?? DateTime(now.year - 20),
                firstDate: DateTime(now.year - UserRanges.birthdayMaxAgeYears),
                lastDate: now,
              );
              if (picked != null) setState(() => _birthday = picked);
            },
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: '生日',
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
              isEmpty: _birthday == null,
              child: Text(
                _birthday == null
                    ? ''
                    : '${_birthday!.year} 年 ${_birthday!.month} 月 ${_birthday!.day} 日',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _bodyInfoFilled ? _nextPage : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                '填寫完成',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
          TextButton(
            onPressed: _nextPage,
            child: Text('下次再說', style: TextStyle(color: Colors.grey.shade500)),
          ),
        ],
      ),
    );
  }

  // 性別選擇按鈕
  Widget _genderChip(String label) {
    final selected = _gender == label;
    return GestureDetector(
      onTap: () => setState(() => _gender = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.orange : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.orange : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.grey.shade600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  // ── 畫面7：收尾 ──
  Widget _buildPage7() {
    return _mascotPage(
      emotion: 'cheer',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _speechBubble('好了！$_nickname，我們準備好了！\n有我陪著你，一定可以的 🐰✨', fontSize: 18),
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
                '出發！🚀',
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

  @override
  Widget build(BuildContext context) {
    // 第1頁（畫面1）沒有返回按鈕；畫面4/5/6 在追問子步驟時也要顯示返回
    final bool showBack =
        _currentPage > 0 ||
        (_currentPage == 3 && _waterStep == 1) ||
        (_currentPage == 4 && _timerStep == 1) ||
        (_currentPage == 5 && _familyStep > 0);

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      // 進度點指示器
      bottomNavigationBar: Container(
        height: 48,
        color: const Color(0xFFFFF8F0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(9, (i) {
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
          // 背景裝飾泡泡（柔和暖色，所有頁面共用）
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _OnboardingBgPainter()),
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
            children: [
              _buildPage1(),
              _buildPage2(),
              _buildPage3(),
              _buildPage4(),
              _buildPage5(),
              _buildFamilyPage(),
              _buildHabitPickerPage(),
              _buildPage6(),
              _buildPage7(),
            ],
          ),
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
    );
  }
}

// 引導頁背景裝飾：柔和暖色泡泡 + 角落葉子，營造溫暖陪伴感
class _OnboardingBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..style = PaintingStyle.fill;
    final w = size.width;
    final h = size.height;

    // 左上 — 大圓
    p.color = const Color(0xFFFFE0B2).withValues(alpha: 0.55);
    canvas.drawCircle(Offset(w * 0.12, h * 0.08), 110, p);
    // 右上 — 中圓
    p.color = const Color(0xFFFFD0A0).withValues(alpha: 0.40);
    canvas.drawCircle(Offset(w * 0.95, h * 0.14), 75, p);
    // 左中 — 小裝飾
    p.color = const Color(0xFFFFCB8A).withValues(alpha: 0.20);
    canvas.drawCircle(Offset(w * 0.02, h * 0.42), 38, p);
    // 右中 — 小裝飾
    p.color = const Color(0xFFFFCB8A).withValues(alpha: 0.22);
    canvas.drawCircle(Offset(w * 0.98, h * 0.48), 32, p);
    // 左下 — 大泡泡
    p.color = const Color(0xFFFFE8C0).withValues(alpha: 0.45);
    canvas.drawCircle(Offset(w * 0.05, h * 0.92), 95, p);
    // 右下 — 中泡泡
    p.color = const Color(0xFFFFD8A0).withValues(alpha: 0.40);
    canvas.drawCircle(Offset(w * 0.90, h * 0.95), 85, p);

    // 左上小葉子
    _drawLeaf(
      canvas,
      Offset(w * 0.22, h * 0.06),
      18,
      const Color(0xFFA8D5A2).withValues(alpha: 0.35),
      rotation: -0.5,
    );
    // 右上小葉子
    _drawLeaf(
      canvas,
      Offset(w * 0.82, h * 0.05),
      14,
      const Color(0xFFB8DFB0).withValues(alpha: 0.35),
      rotation: 0.7,
    );
    // 左下葉子
    _drawLeaf(
      canvas,
      Offset(w * 0.18, h * 0.78),
      16,
      const Color(0xFFA8D5A2).withValues(alpha: 0.30),
      rotation: 1.2,
    );

    // 右上小星星
    _drawStar(
      canvas,
      Offset(w * 0.70, h * 0.10),
      6,
      const Color(0xFFFFC658).withValues(alpha: 0.55),
    );
    // 左中小星星
    _drawStar(
      canvas,
      Offset(w * 0.12, h * 0.25),
      4,
      const Color(0xFFFFC658).withValues(alpha: 0.45),
    );
    // 右中小星星
    _drawStar(
      canvas,
      Offset(w * 0.90, h * 0.30),
      5,
      const Color(0xFFFFC658).withValues(alpha: 0.50),
    );
  }

  void _drawLeaf(
    Canvas canvas,
    Offset c,
    double r,
    Color color, {
    double rotation = 0,
  }) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(rotation);
    final path = Path()
      ..moveTo(0, -r)
      ..quadraticBezierTo(r * 0.9, -r * 0.2, 0, r)
      ..quadraticBezierTo(-r * 0.9, -r * 0.2, 0, -r)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  void _drawStar(Canvas canvas, Offset c, double r, Color color) {
    final path = Path();
    for (int i = 0; i < 10; i++) {
      final angle = -math.pi / 2 + i * math.pi / 5;
      final radius = i.isEven ? r : r * 0.45;
      final x = c.dx + radius * math.cos(angle);
      final y = c.dy + radius * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
