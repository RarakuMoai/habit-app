import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_feedback.dart';
import '../utils/input_formatters.dart';
import '../utils/prefs_keys.dart';
import '../utils/units.dart';
import '../utils/user_validators.dart';
import '../widgets/manual_date_dialog.dart';

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
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

  // 畫面顯示為一週運動天數，內部仍存既有活動量值。
  static const Map<String, String> _activityDayLabels = {
    '久坐': '幾乎沒有',
    '輕度': '1-2 天',
    '中度': '3-4 天',
    '高度': '5 天以上',
  };

  @override
  void initState() {
    super.initState();
    // 欄位變動時重繪，驅動儲存按鈕狀態與範圍錯誤提示
    _nicknameCtrl.addListener(() => setState(() {}));
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
      _mascotCtrl.text = prefs.getString(PrefsKeys.mascotName) ?? '兔咪';
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
      _mascotCtrl.text.trim().isEmpty ? '兔咪' : _mascotCtrl.text.trim(),
    );
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

  // 取得目前單位下顯示用的錯誤訊息（null 表示沒問題）
  String? get _heightError {
    if (_unit == UnitSystem.imperial) {
      final ft = _heightCtrl.text.trim();
      final inches = _heightInCtrl.text.trim();
      if (ft.isEmpty && inches.isEmpty) return null;
      return UserValidators.heightCm(_heightCmFromInputs());
    }
    return UserValidators.height(_heightCtrl.text);
  }

  String? get _weightError => UserValidators.weightIn(_weightCtrl.text, _unit);

  String? get _targetWeightError =>
      UserValidators.targetWeightIn(_targetWeightCtrl.text, _unit);

  // BMI 比例檢查（用公制換算後判斷）
  // 兩個值都進到合理範圍才比對比例（同 onboarding 的 _bmiOddOnboarding），
  // 避免使用者還在改身高/體重的中間值就被誤判
  String? get _bmiError {
    final cm = _heightCmFromInputs();
    final kg = _weightKgFromInput(_weightCtrl);
    if (cm == null || kg == null) return null;
    if (cm < UserRanges.heightMinCm || cm > UserRanges.heightMaxCm) return null;
    if (kg < UserRanges.weightMinKg || kg > UserRanges.weightMaxKg) return null;
    final hM = cm / 100;
    final bmi = kg / (hM * hM);
    if (bmi < UserRanges.bmiMin || bmi > UserRanges.bmiMax) {
      return '身高與體重的比例怪怪的，請再確認';
    }
    return null;
  }

  // 暱稱非空才可儲存，並且填寫的身體資訊必須在合理範圍內
  bool get _canSave =>
      _nicknameCtrl.text.trim().isNotEmpty &&
      _heightError == null &&
      _weightError == null &&
      _targetWeightError == null &&
      UserValidators.birthday(_birthday) == null &&
      _bmiError == null;

  // 單選 Chip（性別 / 活動量共用）：ripple + 觸覺回饋
  Widget _choiceChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? Colors.orange : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? Colors.orange : Colors.grey.shade300,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          splashColor: Colors.orange.withValues(alpha: 0.18),
          highlightColor: Colors.orange.withValues(alpha: 0.08),
          onTap: () {
            if (!selected) playHaptic(HapticLevel.selection);
            onSelected();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.grey.shade600,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 性別選擇 Chip
  Widget _genderChip(String label) => _choiceChip(
    label: label,
    selected: _gender == label,
    onSelected: () => setState(() => _gender = label),
  );

  // 活動量選擇 Chip（顯示為一週運動天數）
  Widget _activityChip(String label) => _choiceChip(
    label: _activityDayLabels[label] ?? label,
    selected: _activityLevel == label,
    onSelected: () => setState(() => _activityLevel = label),
  );

  // 活動量選擇區（用於計算每日總消耗 TDEE）
  Widget _activitySelector() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '一週大概運動幾天？',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _activityDayLabels.keys.map(_activityChip).toList(),
          ),
        ],
      ),
    );
  }

  // 身高 ft/in 兩格並排（imperial 模式專用）
  Widget _ftInFieldRow({
    required TextEditingController ftCtrl,
    required TextEditingController inCtrl,
    String? errorText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ftCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  decoration: InputDecoration(
                    labelText: '身高',
                    suffixText: 'ft',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
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
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: inCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  decoration: InputDecoration(
                    labelText: ' ',
                    suffixText: 'in',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
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
              ),
            ],
          ),
          if (errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                errorText,
                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  // 通用輸入欄位
  Widget _inputField({
    required String label,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    String? suffix,
    bool required = false,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
    String? errorText,
    Widget? suffixWidget,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLength: maxLength,
        inputFormatters: inputFormatters,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          suffixText: suffixWidget == null ? suffix : null,
          suffixIcon: suffixWidget,
          suffixIconConstraints: const BoxConstraints(),
          counterText: '',
          errorText: errorText,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
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
    );
  }

  // 比例明顯不合理時不顯示建議（與 onboarding 統一，見 HealthAdvice）
  ({int low, int high, int suggest, String unit})?
  get _targetWeightSuggestion => HealthAdvice.targetWeightSuggestion(
    heightCm: _heightCmFromInputs(),
    weightKg: _weightKgFromInput(_weightCtrl),
    system: _unit,
  );

  // 目標體重建議：依身高的健康 BMI 範圍（18.5–24），建議值取 BMI 22
  // 需先填身高才顯示；點欄位右側「建議」可一鍵套用
  Widget _targetWeightHint() {
    final suggestion = _targetWeightSuggestion;
    if (suggestion == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(Icons.favorite_outline, size: 14, color: Colors.orange.shade400),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              '健康體重約 ${suggestion.low}–${suggestion.high} ${suggestion.unit}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
        onPressed: () => setState(
          () => _targetWeightCtrl.text = suggestion.suggest.toString(),
        ),
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

  // 將 DateTime 格式化為「yyyy 年 MM 月 dd 日」顯示用
  String _formatDate(DateTime d) =>
      '${d.year} 年 '
      '${d.month.toString().padLeft(2, '0')} 月 '
      '${d.day.toString().padLeft(2, '0')} 日';

  // 手動輸入生日（寬鬆解析：2000-1-1 / 20000101 / 2000年1月1日 都可）
  Future<void> _manualBirthdayInput() async {
    final now = DateTime.now();
    final picked = await showManualDateDialog(
      context,
      initial: _birthday,
      firstDate: DateTime(now.year - UserRanges.birthdayMaxAgeYears),
      lastDate: now,
      title: '輸入生日',
    );
    if (picked != null) setState(() => _birthday = picked);
  }

  // 生日選擇欄位（點擊開啟日曆；鍵盤鈕開手動輸入）
  Widget _birthdayField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: _birthday ?? DateTime(now.year - 20),
            firstDate: DateTime(now.year - UserRanges.birthdayMaxAgeYears),
            lastDate: now,
            // 自帶輸入模式解析太死板，手動輸入走 _manualBirthdayInput
            initialEntryMode: DatePickerEntryMode.calendarOnly,
          );
          if (picked != null) setState(() => _birthday = picked);
        },
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: '生日',
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.keyboard_alt_outlined,
                    size: 18,
                    color: Colors.orange,
                  ),
                  visualDensity: VisualDensity.compact,
                  tooltip: '直接輸入',
                  onPressed: _manualBirthdayInput,
                ),
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Icon(
                    Icons.calendar_today_outlined,
                    size: 18,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
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
          // isEmpty=true 時 label 停在中間（未選狀態）
          isEmpty: _birthday == null,
          child: Text(
            _birthday == null ? '' : _formatDate(_birthday!),
            style: const TextStyle(fontSize: 16),
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
        backgroundColor: Colors.orange,
        title: const Text('基本資料', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loaded
          ? Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      // 暱稱（必填）
                      _inputField(
                        label: '暱稱',
                        controller: _nicknameCtrl,
                        required: true,
                        maxLength: 12,
                      ),
                      // 暱稱為空時顯示提示（其他欄位的錯誤各自在欄位下方顯示）
                      if (_nicknameCtrl.text.trim().isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '暱稱不能為空',
                            style: TextStyle(
                              color: Colors.red.shade400,
                              fontSize: 12,
                            ),
                          ),
                        ),

                      // 吉祥物名字
                      _inputField(
                        label: '吉祥物名字',
                        controller: _mascotCtrl,
                        maxLength: 12,
                      ),

                      // 性別選擇
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '性別',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                _genderChip('男'),
                                const SizedBox(width: 8),
                                _genderChip('女'),
                                const SizedBox(width: 8),
                                _genderChip('不透露'),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // 身高（依單位顯示一格或兩格）
                      if (_unit == UnitSystem.imperial)
                        _ftInFieldRow(
                          ftCtrl: _heightCtrl,
                          inCtrl: _heightInCtrl,
                          errorText: _heightError,
                        )
                      else
                        _inputField(
                          label: '身高',
                          controller: _heightCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          suffix: 'cm',
                          inputFormatters: [maxValueFormatter(999)],
                          errorText: _heightError,
                        ),

                      // 體重
                      _inputField(
                        label: '體重',
                        controller: _weightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        suffix: UnitFormat.weightLabel(_unit),
                        inputFormatters: [maxValueFormatter(999)],
                        // 個別範圍錯誤優先；都過了才顯示 BMI 比例錯誤
                        errorText: _weightError ?? _bmiError,
                      ),

                      // 目標體重（選填）
                      _inputField(
                        label: '目標體重',
                        controller: _targetWeightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        suffix: UnitFormat.weightLabel(_unit),
                        suffixWidget: _targetWeightSuggestSuffix(),
                        inputFormatters: [maxValueFormatter(999)],
                        errorText: _targetWeightError,
                      ),

                      // 目標體重建議（依身高的健康範圍）
                      _targetWeightHint(),

                      // 生日（選填，點擊開啟日期選擇器）
                      _birthdayField(),

                      // 活動量（用於計算每日總消耗 TDEE）
                      _activitySelector(),
                    ],
                  ),
                ),

                // 底部儲存按鈕
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        // 暱稱為空時 disabled
                        onPressed: _canSave ? _save : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          disabledBackgroundColor: Colors.grey.shade300,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          '儲存',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}
