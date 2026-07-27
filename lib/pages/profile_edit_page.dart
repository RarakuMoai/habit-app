import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/input_formatters.dart';
import '../utils/mascot.dart';
import '../utils/prefs_keys.dart';
import '../utils/units.dart';
import '../utils/user_validators.dart';
import '../widgets/birthday_picker.dart';

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  // 儲存動作用珊瑚橘；內容分區各自有識別色，對齊功能開關頁的彩色圖示語彙。
  static const Color _accent = Color(0xFFF07961);
  static const Color _identityAccent = Color(0xFFF07961);
  static const Color _basicsAccent = Color(0xFF9875D1);
  static const Color _bodyAccent = Color(0xFF329888);
  static const Color _activityAccent = Color(0xFFE58A34);

  final TextEditingController _nicknameCtrl = TextEditingController();
  final TextEditingController _mascotCtrl = TextEditingController();
  // 身高：metric 時是 cm；imperial 時是 ft（搭配 _heightInCtrl 的 in）
  final TextEditingController _heightCtrl = TextEditingController();
  final TextEditingController _heightInCtrl = TextEditingController();
  // 體重 / 目標體重：依當下單位是 kg 或 lb
  final TextEditingController _weightCtrl = TextEditingController();
  final TextEditingController _targetWeightCtrl = TextEditingController();

  String _gender = '';
  DateTime? _birthday; // 生日（選填）
  String _activityLevel = ''; // 活動量（內部為久坐/輕度/中度/高度），用於計算 TDEE
  UnitSystem _unit = UnitSystem.metric;
  bool _loaded = false;

  // 性別與活動量的「內部儲存值」。prefs 與跨頁邏輯（weight/water page 的
  // TDEE 計算）都比對這些中文字串，i18n 只換顯示標籤、不動儲存值。
  static const List<String> _genders = ['男', '女', '不透露'];
  static const List<String> _activityLevels = ['久坐', '輕度', '中度', '高度'];

  // 內部值 → 顯示標籤（畫面顯示為一週運動天數）。
  String _genderLabel(AppLocalizations l10n, String value) => switch (value) {
    '男' => l10n.genderMale,
    '女' => l10n.genderFemale,
    _ => l10n.genderUndisclosed,
  };

  String _activityLabel(AppLocalizations l10n, String value) => switch (value) {
    '久坐' => l10n.activityAlmostNone,
    '輕度' => l10n.activityDays1to2,
    '中度' => l10n.activityDays3to4,
    _ => l10n.activityDays5plus,
  };

  @override
  void initState() {
    super.initState();
    // 欄位變動時重繪，驅動儲存按鈕狀態與範圍錯誤提示
    _nicknameCtrl.addListener(() => setState(() {}));
    // 兔咪名字同步反映在頁面介紹文案，不再固定顯示預設名。
    _mascotCtrl.addListener(() => setState(() {}));
    _heightCtrl.addListener(() => setState(() {}));
    _heightInCtrl.addListener(() => setState(() {}));
    _weightCtrl.addListener(() => setState(() {}));
    _targetWeightCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _mascotCtrl.dispose();
    _heightCtrl.dispose();
    _heightInCtrl.dispose();
    _weightCtrl.dispose();
    _targetWeightCtrl.dispose();
    super.dispose();
  }

  // 整數不顯示小數點，否則保留一位
  String _formatDouble(double v) {
    return v == v.truncateToDouble()
        ? v.toInt().toString()
        : v.toStringAsFixed(1);
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final unit = UnitSystem.load(prefs);
    final h = prefs.getDouble(PrefsKeys.userHeight);
    final w = prefs.getDouble(PrefsKeys.userWeight);
    final tw = prefs.getDouble(PrefsKeys.targetWeight);
    final bday = prefs.getString(PrefsKeys.userBirthday);
    setState(() {
      _unit = unit;
      _nicknameCtrl.text = prefs.getString(PrefsKeys.userNickname) ?? '';
      _mascotCtrl.text =
          prefs.getString(PrefsKeys.mascotName) ?? MascotName.fallback;
      _gender = prefs.getString(PrefsKeys.userGender) ?? '';
      _activityLevel = prefs.getString(PrefsKeys.userActivityLevel) ?? '';
      if (h != null) {
        if (unit == UnitSystem.imperial) {
          final (ft, inches) = UnitConvert.cmToFtIn(h);
          _heightCtrl.text = ft.toString();
          _heightInCtrl.text = inches.toString();
        } else {
          _heightCtrl.text = _formatDouble(h);
        }
      }
      if (w != null) {
        _weightCtrl.text = unit == UnitSystem.imperial
            ? UnitConvert.kgToLb(w).round().toString()
            : _formatDouble(w);
      }
      if (tw != null) {
        _targetWeightCtrl.text = unit == UnitSystem.imperial
            ? UnitConvert.kgToLb(tw).round().toString()
            : _formatDouble(tw);
      }
      // 從 yyyy-MM-dd 字串還原 DateTime
      if (bday != null) _birthday = DateTime.tryParse(bday);
      _loaded = true;
    });
  }

  // 取得目前單位下身高的公制值（cm）；無法解析回 null。
  double? _heightCmFromInputs() {
    if (_unit == UnitSystem.imperial) {
      final ft = int.tryParse(_heightCtrl.text.trim());
      final inches = int.tryParse(_heightInCtrl.text.trim());
      if (ft == null && inches == null) return null;
      return UnitConvert.ftInToCm(ft ?? 0, inches ?? 0);
    }
    return double.tryParse(_heightCtrl.text.trim());
  }

  // 取得目前單位下體重的公制值（kg）；無法解析回 null。
  double? _weightKgFromInput(TextEditingController c) {
    final v = double.tryParse(c.text.trim());
    if (v == null) return null;
    if (_unit == UnitSystem.imperial) return UnitConvert.lbToKg(v);
    return v;
  }

  // 按下「儲存」時一次寫入所有欄位，然後返回
  Future<void> _save() async {
    playHaptic(HapticLevel.light);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.userNickname, _nicknameCtrl.text.trim());
    await prefs.setString(
      PrefsKeys.mascotName,
      _mascotCtrl.text.trim().isEmpty
          ? MascotName.fallback
          : _mascotCtrl.text.trim(),
    );
    // 同步全域名字，帶 {name} 的系統文案立刻換掉
    MascotName.set(_mascotCtrl.text);
    if (_gender.isNotEmpty) {
      await prefs.setString(PrefsKeys.userGender, _gender);
    }
    if (_activityLevel.isNotEmpty) {
      await prefs.setString(PrefsKeys.userActivityLevel, _activityLevel);
    }
    final hCm = _heightCmFromInputs();
    if (hCm != null &&
        hCm >= UserRanges.heightMinCm &&
        hCm <= UserRanges.heightMaxCm) {
      await prefs.setDouble(PrefsKeys.userHeight, hCm);
    }
    final wKg = _weightKgFromInput(_weightCtrl);
    if (wKg != null &&
        wKg >= UserRanges.weightMinKg &&
        wKg <= UserRanges.weightMaxKg) {
      await prefs.setDouble(PrefsKeys.userWeight, wKg);
    }
    // 目標體重（選填）
    final twKg = _weightKgFromInput(_targetWeightCtrl);
    if (twKg != null &&
        twKg >= UserRanges.targetWeightMinKg &&
        twKg <= UserRanges.targetWeightMaxKg) {
      await prefs.setDouble(PrefsKeys.targetWeight, twKg);
    }
    // 生日（選填），以 yyyy-MM-dd 格式儲存
    if (_birthday != null) {
      final b = _birthday!;
      await prefs.setString(
        PrefsKeys.userBirthday,
        '${b.year.toString().padLeft(4, '0')}-'
        '${b.month.toString().padLeft(2, '0')}-'
        '${b.day.toString().padLeft(2, '0')}',
      );
    }
    if (mounted) Navigator.pop(context);
  }

  AppLocalizations get _l10n => AppLocalizations.of(context);

  String get _displayMascotName {
    final name = _mascotCtrl.text.trim();
    return name.isEmpty ? MascotName.fallback : name;
  }

  // 取得目前單位下顯示用的錯誤訊息（null 表示沒問題）
  String? get _heightError {
    if (_unit == UnitSystem.imperial) {
      final ft = _heightCtrl.text.trim();
      final inches = _heightInCtrl.text.trim();
      if (ft.isEmpty && inches.isEmpty) return null;
      return UserValidators.heightCm(_l10n, _heightCmFromInputs());
    }
    return UserValidators.height(_l10n, _heightCtrl.text);
  }

  String? get _weightError =>
      UserValidators.weightIn(_l10n, _weightCtrl.text, _unit);

  String? get _targetWeightError =>
      UserValidators.targetWeightIn(_l10n, _targetWeightCtrl.text, _unit);

  // BMI 比例檢查（用公制換算後判斷）
  String? get _bmiError {
    final cm = _heightCmFromInputs();
    final kg = _weightKgFromInput(_weightCtrl);
    if (cm == null || kg == null) return null;
    if (cm < UserRanges.heightMinCm || cm > UserRanges.heightMaxCm) return null;
    if (kg < UserRanges.weightMinKg || kg > UserRanges.weightMaxKg) return null;
    final hM = cm / 100;
    final bmi = kg / (hM * hM);
    if (bmi < UserRanges.bmiMin || bmi > UserRanges.bmiMax) {
      return _l10n.valBmiImplausible;
    }
    return null;
  }

  // 暱稱非空才可儲存，並且填寫的身體資訊必須在合理範圍內
  bool get _canSave =>
      _nicknameCtrl.text.trim().isNotEmpty &&
      _heightError == null &&
      _weightError == null &&
      _targetWeightError == null &&
      UserValidators.birthday(_l10n, _birthday) == null &&
      _bmiError == null;

  // ── 彩色分區版型：大標題、淡色卡面、各區獨立識別色。──

  Widget _introCard() {
    return Container(
      key: const ValueKey('profile-edit-intro'),
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.fromLTRB(18, 17, 16, 17),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE6D9), Color(0xFFFFF2D9), Color(0xFFF2EAFE)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _identityAccent.withValues(alpha: 0.16)),
        boxShadow: AppShadows.flat,
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.78),
              shape: BoxShape.circle,
              border: Border.all(
                color: _identityAccent.withValues(alpha: 0.18),
              ),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: _identityAccent,
              size: 27,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _l10n.peIntroTitle(_displayMascotName),
                  style: const TextStyle(
                    fontSize: 20,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                    color: AppInk.strong,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _l10n.peIntroSubtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: AppInk.soft,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accent,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 24, 2, 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.11),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                    color: AppInk.strong,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: AppInk.soft,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 卡片外殼：分區色只淡淡進入底色與描邊，保留輸入內容的清晰度。
  Widget _card({
    required Widget child,
    required Color accent,
    EdgeInsets? padding,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: padding ?? const EdgeInsets.fromLTRB(15, 14, 14, 15),
      decoration: BoxDecoration(
        color: Color.lerp(AppSurfaces.card, accent, 0.035),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
        boxShadow: [
          ...AppShadows.flat,
          BoxShadow(
            color: accent.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }

  // 含圖示與標籤的文字輸入卡
  Widget _textCard({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    bool required = false,
    TextInputType keyboardType = TextInputType.text,
    String? suffix,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
    String? errorText,
    Widget? trailing,
    String? hint,
    required Color accent,
  }) {
    return _card(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.11),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppInk.strong,
                ),
              ),
              if (required)
                Text(
                  ' *',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Colors.red.shade400,
                  ),
                ),
              const Spacer(),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLength: maxLength,
            inputFormatters: inputFormatters,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppInk.strong,
            ),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              hintText: hint,
              hintStyle: const TextStyle(color: AppInk.faint, fontSize: 16),
              suffixText: suffix,
              suffixStyle: const TextStyle(
                color: AppInk.soft,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.78),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 13,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: accent.withValues(alpha: 0.16)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: accent.withValues(alpha: 0.16)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: accent, width: 1.6),
              ),
            ),
          ),
          if (errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                errorText,
                style: TextStyle(color: Colors.red.shade400, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  // 身高 ft/in 兩格並排（imperial 模式專用），同卡片風格
  Widget _ftInCard({String? errorText}) {
    InputDecoration deco(String suffix) => InputDecoration(
      isDense: true,
      counterText: '',
      suffixText: suffix,
      suffixStyle: const TextStyle(
        color: AppInk.soft,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.78),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE8DDD4)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE8DDD4)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _bodyAccent, width: 1.6),
      ),
    );
    return _card(
      accent: _bodyAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _bodyAccent.withValues(alpha: 0.11),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.straighten_rounded,
                  size: 18,
                  color: _bodyAccent,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _l10n.heightLabel,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppInk.strong,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _heightCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppInk.strong,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  decoration: deco('ft'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _heightInCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppInk.strong,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  decoration: deco('in'),
                ),
              ),
            ],
          ),
          if (errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                errorText,
                style: TextStyle(color: Colors.red.shade400, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  // 單選 Chip（性別 / 活動量共用）
  Widget _choiceChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
    required Color accent,
  }) {
    return Material(
      color: selected ? accent : accent.withValues(alpha: 0.065),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          if (!selected) playHaptic(HapticLevel.selection);
          onSelected();
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? accent : accent.withValues(alpha: 0.20),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppInk.soft,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  // 性別 / 活動量卡（標籤 + 一排 chip）
  Widget _chipsCard({
    required IconData icon,
    required String label,
    required List<Widget> chips,
    required Color accent,
  }) {
    return _card(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.11),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppInk.strong,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        ],
      ),
    );
  }

  // 比例明顯不合理時不顯示建議（與 onboarding 統一，見 HealthAdvice）
  ({int low, int high, int suggest, String unit})?
  get _targetWeightSuggestion => HealthAdvice.targetWeightSuggestion(
    heightCm: _heightCmFromInputs(),
    weightKg: _weightKgFromInput(_weightCtrl),
    system: _unit,
  );

  Widget? _targetWeightSuggestSuffix() {
    final suggestion = _targetWeightSuggestion;
    if (suggestion == null) return null;
    return Material(
      color: _bodyAccent.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          playHaptic(HapticLevel.selection);
          setState(
            () => _targetWeightCtrl.text = suggestion.suggest.toString(),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            _l10n.peSuggestChip(suggestion.suggest, suggestion.unit),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF267B6E),
            ),
          ),
        ),
      ),
    );
  }

  // 將 DateTime 格式化為日期顯示（格式在 ARB 的 dateYmd，隨語言變）
  String _formatDate(DateTime d) => _l10n.dateYmd(
    d.year,
    d.month.toString().padLeft(2, '0'),
    d.day.toString().padLeft(2, '0'),
  );

  // 生日卡：點擊開啟「月曆 + 手動輸入」單一畫面選擇器
  Widget _birthdayCard() {
    final now = DateTime.now();
    return _card(
      accent: _basicsAccent,
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () async {
            final picked = await showBirthdayPicker(
              context,
              initial: _birthday,
              firstDate: DateTime(now.year - UserRanges.birthdayMaxAgeYears),
              lastDate: now,
              accent: _basicsAccent,
            );
            if (picked != null) setState(() => _birthday = picked);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _basicsAccent.withValues(alpha: 0.11),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.cake_rounded,
                    size: 18,
                    color: _basicsAccent,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _l10n.birthdayLabel,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppInk.strong,
                  ),
                ),
                const Spacer(),
                Text(
                  _birthday == null
                      ? _l10n.notSetLabel
                      : _formatDate(_birthday!),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _birthday == null ? AppInk.faint : AppInk.strong,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 18,
                  color: _basicsAccent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF8F0),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppInk.strong),
        title: Text(
          _l10n.basicInfoTitle,
          style: const TextStyle(
            color: AppInk.strong,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    children: [
                      _introCard(),
                      _sectionTitle(
                        icon: Icons.badge_rounded,
                        title: _l10n.peSectionName,
                        subtitle: _l10n.peSectionNameSubtitle(
                          _displayMascotName,
                        ),
                        accent: _identityAccent,
                      ),
                      _textCard(
                        icon: Icons.person_rounded,
                        label: _l10n.peNicknameLabel,
                        controller: _nicknameCtrl,
                        required: true,
                        maxLength: 12,
                        hint: _l10n.peNicknameHint,
                        errorText: _nicknameCtrl.text.trim().isEmpty
                            ? _l10n.peNicknameRequired
                            : null,
                        accent: _identityAccent,
                      ),
                      _textCard(
                        icon: Icons.pets_rounded,
                        label: _l10n.peMascotNameLabel,
                        controller: _mascotCtrl,
                        // 與 onboarding 一致：限長是為了防破版，數的是顯示
                        // 寬度而非字元數（中文 6 字＝英文 12 字元）。
                        inputFormatters: const [
                          DisplayWidthLimitingFormatter(kMascotNameMaxUnits),
                        ],
                        hint: _l10n.mascotDefaultName,
                        accent: _identityAccent,
                      ),

                      _sectionTitle(
                        icon: Icons.face_rounded,
                        title: _l10n.peSectionAbout,
                        subtitle: _l10n.peSectionAboutSubtitle,
                        accent: _basicsAccent,
                      ),
                      _chipsCard(
                        icon: Icons.wc_rounded,
                        label: _l10n.genderLabel,
                        accent: _basicsAccent,
                        chips: [
                          for (final g in _genders)
                            _choiceChip(
                              label: _genderLabel(_l10n, g),
                              selected: _gender == g,
                              onSelected: () => setState(() => _gender = g),
                              accent: _basicsAccent,
                            ),
                        ],
                      ),
                      _birthdayCard(),

                      _sectionTitle(
                        icon: Icons.straighten_rounded,
                        title: _l10n.peSectionBody,
                        subtitle: _l10n.peSectionBodySubtitle,
                        accent: _bodyAccent,
                      ),
                      if (_unit == UnitSystem.imperial)
                        _ftInCard(errorText: _heightError)
                      else
                        _textCard(
                          icon: Icons.straighten_rounded,
                          label: _l10n.heightLabel,
                          controller: _heightCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          suffix: 'cm',
                          // 公制身高：含自動補小數（例 1708 → 170.8）
                          inputFormatters: [
                            bodyMetricFormatter(UserRanges.heightMaxCm),
                          ],
                          errorText: _heightError,
                          hint: '170',
                          accent: _bodyAccent,
                        ),
                      _textCard(
                        icon: Icons.monitor_weight_rounded,
                        label: _l10n.weightInputLabel,
                        controller: _weightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        suffix: UnitFormat.weightLabel(_unit),
                        // 英制(lb)維持整數；公制含自動補小數（例 705 → 70.5）
                        inputFormatters: [
                          if (_unit == UnitSystem.imperial)
                            maxValueFormatter(999)
                          else
                            bodyMetricFormatter(UserRanges.weightMaxKg),
                        ],
                        errorText: _weightError ?? _bmiError,
                        hint: '60',
                        accent: _bodyAccent,
                      ),
                      _textCard(
                        icon: Icons.flag_rounded,
                        label: _l10n.targetWeightLabel,
                        controller: _targetWeightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        suffix: UnitFormat.weightLabel(_unit),
                        inputFormatters: [
                          if (_unit == UnitSystem.imperial)
                            maxValueFormatter(999)
                          else
                            bodyMetricFormatter(UserRanges.targetWeightMaxKg),
                        ],
                        errorText: _targetWeightError,
                        trailing: _targetWeightSuggestSuffix(),
                        hint: _l10n.optionalHint,
                        accent: _bodyAccent,
                      ),

                      _sectionTitle(
                        icon: Icons.directions_run_rounded,
                        title: _l10n.peSectionActivity,
                        subtitle: _l10n.peSectionActivitySubtitle,
                        accent: _activityAccent,
                      ),
                      _chipsCard(
                        icon: Icons.local_fire_department_rounded,
                        label: _l10n.peActivityQuestion,
                        accent: _activityAccent,
                        chips: [
                          for (final k in _activityLevels)
                            _choiceChip(
                              label: _activityLabel(_l10n, k),
                              selected: _activityLevel == k,
                              onSelected: () =>
                                  setState(() => _activityLevel = k),
                              accent: _activityAccent,
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),

                // 底部儲存按鈕（固定）
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _canSave ? _save : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: _accent,
                          disabledBackgroundColor: const Color(0xFFE6DACE),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.check_rounded, size: 20),
                        label: Text(
                          _l10n.commonSave,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
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
