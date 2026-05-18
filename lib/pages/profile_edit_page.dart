import 'package:flutter/material.dart';
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
  bool _loaded = false;

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

  // 數值範圍檢查：空字串或合法值回傳 null，否則回傳錯誤訊息（供 errorText 用）
  String? _rangeError(String text, num min, num max) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null) return '請輸入數字';
    if (v < min || v > max) return '請輸入 $min–$max 之間的數字';
    return null;
  }

  // 暱稱非空，且身高體重在合理範圍內才可儲存
  bool get _canSave =>
      _nicknameCtrl.text.trim().isNotEmpty &&
      _rangeError(_heightCtrl.text, 1, 300) == null &&
      _rangeError(_weightCtrl.text, 1, 500) == null &&
      _rangeError(_targetWeightCtrl.text, 1, 500) == null;

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

  // 通用輸入欄位
  Widget _inputField({
    required String label,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    String? suffix,
    bool required = false,
    String? errorText,
    int? maxLength,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLength: maxLength,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          suffixText: suffix,
          errorText: errorText,
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
                        errorText: _rangeError(_heightCtrl.text, 1, 300),
                      ),

                      // 體重
                      _inputField(
                        label: '體重',
                        controller: _weightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        suffix: 'kg',
                        errorText: _rangeError(_weightCtrl.text, 1, 500),
                      ),

                      // 目標體重（選填）
                      _inputField(
                        label: '目標體重',
                        controller: _targetWeightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        suffix: 'kg',
                        errorText: _rangeError(_targetWeightCtrl.text, 1, 500),
                      ),

                      // 生日（選填，點擊開啟日期選擇器）
                      _birthdayField(),
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
