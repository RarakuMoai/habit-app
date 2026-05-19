import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final TextEditingController _nicknameCtrl = TextEditingController();
  final TextEditingController _mascotCtrl = TextEditingController();
  final TextEditingController _heightCtrl = TextEditingController();
  final TextEditingController _weightCtrl = TextEditingController();
  final TextEditingController _targetWeightCtrl = TextEditingController();

  String _gender = '';
  DateTime? _birthday; // 生日（選填）
  String _activityLevel = ''; // 活動量（久坐/輕度/中度/高度），用於計算 TDEE
  bool _loaded = false;

  // 活動量等級與說明
  static const Map<String, String> _activityDesc = {
    '久坐': '幾乎不運動',
    '輕度': '每週運動 1–3 天',
    '中度': '每週運動 3–5 天',
    '高度': '每週運動 6–7 天',
  };

  @override
  void initState() {
    super.initState();
    // 欄位變動時重繪，驅動儲存按鈕狀態與範圍錯誤提示
    _nicknameCtrl.addListener(() => setState(() {}));
    _heightCtrl.addListener(() => setState(() {}));
    _weightCtrl.addListener(() => setState(() {}));
    _targetWeightCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _mascotCtrl.dispose();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _targetWeightCtrl.dispose();
    super.dispose();
  }

  // 整數不顯示小數點，否則保留一位
  String _formatDouble(double v) {
    return v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final double? h = prefs.getDouble('user_height');
    final double? w = prefs.getDouble('user_weight');
    final double? tw = prefs.getDouble('target_weight');
    final String? bday = prefs.getString('user_birthday');
    setState(() {
      _nicknameCtrl.text = prefs.getString('user_nickname') ?? '';
      _mascotCtrl.text = prefs.getString('mascot_name') ?? '兔咪';
      _gender = prefs.getString('user_gender') ?? '';
      _activityLevel = prefs.getString('user_activity_level') ?? '';
      if (h != null) _heightCtrl.text = _formatDouble(h);
      if (w != null) _weightCtrl.text = _formatDouble(w);
      if (tw != null) _targetWeightCtrl.text = _formatDouble(tw);
      // 從 yyyy-MM-dd 字串還原 DateTime
      if (bday != null) _birthday = DateTime.tryParse(bday);
      _loaded = true;
    });
  }

  // 按下「儲存」時一次寫入所有欄位，然後返回
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_nickname', _nicknameCtrl.text.trim());
    await prefs.setString(
      'mascot_name',
      _mascotCtrl.text.trim().isEmpty ? '兔咪' : _mascotCtrl.text.trim(),
    );
    if (_gender.isNotEmpty) await prefs.setString('user_gender', _gender);
    if (_activityLevel.isNotEmpty) {
      await prefs.setString('user_activity_level', _activityLevel);
    }
    final h = double.tryParse(_heightCtrl.text.trim());
    if (h != null) await prefs.setDouble('user_height', h);
    final w = double.tryParse(_weightCtrl.text.trim());
    if (w != null) await prefs.setDouble('user_weight', w);
    // 目標體重（選填）
    final tw = double.tryParse(_targetWeightCtrl.text.trim());
    if (tw != null) await prefs.setDouble('target_weight', tw);
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
    if (mounted) Navigator.pop(context);
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

  // 暱稱非空才可儲存
  bool get _canSave => _nicknameCtrl.text.trim().isNotEmpty;

  // 性別選擇 Chip
  Widget _genderChip(String label) {
    final selected = _gender == label;
    return GestureDetector(
      onTap: () => setState(() => _gender = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

  // 活動量選擇 Chip
  Widget _activityChip(String label) {
    final selected = _activityLevel == label;
    return GestureDetector(
      onTap: () => setState(() => _activityLevel = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

  // 活動量選擇區（用於計算每日總消耗 TDEE）
  Widget _activitySelector() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '活動量',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _activityDesc.keys.map(_activityChip).toList(),
          ),
          if (_activityLevel.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              _activityDesc[_activityLevel]!,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ],
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
          suffixText: suffix,
          counterText: '',
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  // 目標體重建議：依身高的健康 BMI 範圍（18.5–24），建議值取 BMI 22
  // 需先填身高才顯示；點「建議」可一鍵套用
  Widget _targetWeightHint() {
    final h = double.tryParse(_heightCtrl.text.trim());
    if (h == null || h < 1 || h > 300) return const SizedBox.shrink();
    final hM = h / 100;
    final low = (18.5 * hM * hM).round();
    final high = (24 * hM * hM).round();
    final suggest = (22 * hM * hM).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(Icons.favorite_outline, size: 14, color: Colors.orange.shade400),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              '健康體重約 $low–$high kg',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          GestureDetector(
            onTap: () =>
                setState(() => _targetWeightCtrl.text = suggest.toString()),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Text(
                '建議 $suggest kg',
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

  // 將 DateTime 格式化為「yyyy 年 MM 月 dd 日」顯示用
  String _formatDate(DateTime d) =>
      '${d.year} 年 '
      '${d.month.toString().padLeft(2, '0')} 月 '
      '${d.day.toString().padLeft(2, '0')} 日';

  // 生日選擇欄位（點擊開啟日期選擇器）
  Widget _birthdayField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: _birthday ?? DateTime(now.year - 20),
            firstDate: DateTime(1900),
            lastDate: now,
          );
          if (picked != null) setState(() => _birthday = picked);
        },
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: '生日',
            suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18, color: Colors.orange),
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
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                      // 暱稱為空時顯示提示
                      if (!_canSave)
                        Padding(
                          padding: const EdgeInsets.only(top: 0, bottom: 8),
                          child: Text(
                            '暱稱不能為空',
                            style: TextStyle(color: Colors.red.shade400, fontSize: 12),
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
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
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

                      // 身高
                      _inputField(
                        label: '身高',
                        controller: _heightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        suffix: 'cm',
                        inputFormatters: [_maxValueFormatter(999)],
                      ),

                      // 體重
                      _inputField(
                        label: '體重',
                        controller: _weightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        suffix: 'kg',
                        inputFormatters: [_maxValueFormatter(999)],
                      ),

                      // 目標體重（選填）
                      _inputField(
                        label: '目標體重',
                        controller: _targetWeightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        suffix: 'kg',
                        inputFormatters: [_maxValueFormatter(999)],
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
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
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
