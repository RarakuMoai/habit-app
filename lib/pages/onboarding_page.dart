import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // 畫面1：打字動畫
  final List<String> _lines = ['嗯…啊…（伸懶腰）我醒了！', '嗨！我是兔咪 🐰', '我會陪你一起養成好習慣！'];
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
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  DateTime? _birthday; // 生日（選填）

  // 用戶暱稱（畫面3填完後存起來）
  String _nickname = '';

  @override
  void initState() {
    super.initState();
    _nicknameController.addListener(() => setState(() {}));
    _heightController.addListener(() => setState(() {}));
    _weightController.addListener(() => setState(() {}));
    // 等第一幀渲染完成（Offstage 預熱字形後）再啟動打字動畫
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startTyping();
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _pageController.dispose();
    _mascotController.dispose();
    _nicknameController.dispose();
    _heightController.dispose();
    _weightController.dispose();
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
    if (_currentPage < 7) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
      setState(() => _currentPage++);
    }
  }

  bool get _bodyInfoFilled =>
      _gender.isNotEmpty &&
      double.tryParse(_heightController.text.trim()) != null &&
      double.tryParse(_weightController.text.trim()) != null &&
      _birthday != null;

  // 回上一步：畫面4/5/6 若在追問子步驟，先退回初始選項；否則回上一畫面
  void _handleBack() {
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
    final heightVal = double.tryParse(_heightController.text);
    if (heightVal != null) await prefs.setDouble('user_height', heightVal);
    final weightVal = double.tryParse(_weightController.text);
    if (weightVal != null) {
      await prefs.setDouble('user_weight', weightVal);
      await prefs.setBool('weight_tracking_enabled', true);
      // 自動新增體重紀錄習慣
      await _addWeightHabit(prefs);
    }
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
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween(begin: 0.9, end: 1.0).animate(anim),
            child: child,
          ),
        ),
        child: Image.asset(
          'assets/images/mascot/tumi_$emotion.png',
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
  // 引導頁外框：空間足夠時置中，鍵盤彈出或螢幕較小時可捲動，避免 RenderFlex 溢出
  Widget _scrollableCenter(Widget child) => Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: child,
          ),
        ),
      );

  Widget _buildPage1() {
    // 依打字進度切換情緒：第1句剛醒(sleep) → 自我介紹(neutral) → 陪伴宣告(smile)
    final wakeEmotion = _page1Done
        ? 'smile'
        : (_lineIndex == 0
            ? 'sleep'
            : (_lineIndex == 1 ? 'neutral_front' : 'smile'));
    return _scrollableCenter(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 吉祥物跳動動畫
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (context, val, child) =>
                Transform.scale(scale: val, child: child),
            child: _mascot(size: 160, emotion: wakeEmotion),
          ),
          const SizedBox(height: 32),
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
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _mascot(size: 120, emotion: 'smile'),
              const SizedBox(height: 20),
              _speechBubble('對了，你可以幫我取個名字！'),
              const SizedBox(height: 32),
              TextField(
                controller: _mascotController,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  hintText: '幫我取個名字',
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
                      () => _mascotName =
                          _mascotController.text.trim().isEmpty
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
        ),
      ),
    );
  }

  // ── 畫面3：用戶暱稱 ──
  Widget _buildPage3() {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _mascot(size: 120, emotion: 'expect'),
              const SizedBox(height: 20),
              _speechBubble('$_mascotName：那…你呢？\n我以後要怎麼叫你？'),
              const SizedBox(height: 24),
              TextField(
                controller: _nicknameController,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  hintText: '輸入你的暱稱',
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
                            () => _nickname =
                                _nicknameController.text.trim(),
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
        ),
      ),
    );
  }

  // ── 畫面4：喝水功能引導 ──
  Widget _buildPage4() {
    return _scrollableCenter(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _mascot(size: 120, emotion: 'neutral_front'),
          const SizedBox(height: 20),
          if (_waterStep == 0) ...[
            _speechBubble('$_nickname！好名字～\n對了，你平常有在注意喝水嗎？'),
            const SizedBox(height: 32),
            _optionButton('有，但常常忘記', () {
              setState(() {
                _waterStep = 1;
                _waterFollowup = '要不要讓我幫你記錄喝水呢？💧';
              });
            }),
            _optionButton('有在注意', () {
              setState(() {
                _waterStep = 1;
                _waterFollowup = '哇，很棒！要不要讓我一起幫你記錄？';
              });
            }),
            _optionButton('沒特別想到', () {
              setState(() {
                _waterStep = 1;
                _waterFollowup = '要不要讓我幫你記錄喝水呢？💧';
              });
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
    return _scrollableCenter(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _mascot(size: 120, emotion: 'neutral_front'),
          const SizedBox(height: 20),
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
    return _scrollableCenter(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _mascot(size: 120, emotion: 'neutral_front'),
          const SizedBox(height: 20),
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
  Widget _buildPage6() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 16),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _mascot(size: 96, emotion: 'smile'),
          const SizedBox(height: 14),
          _speechBubble('想讓我更了解你嗎？\n如果你有減重或健康目標，\n可以告訴我身高體重～'),
          const SizedBox(height: 6),
          Text(
            '不想說也完全沒關係！',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
          const SizedBox(height: 16),
          // 可滾動欄位區（佔據中段空間）
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
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
                  // 身高
                  TextField(
                    controller: _heightController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '身高（cm）',
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
                  ),
                  const SizedBox(height: 10),
                  // 體重
                  TextField(
                    controller: _weightController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '體重（kg）',
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
                  ),
                  const SizedBox(height: 10),
                  // 生日（選填，點擊開啟日期選擇器）
                  InkWell(
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
                        suffixIcon: const Icon(
                          Icons.calendar_today_outlined,
                          size: 18,
                          color: Colors.orange,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: Colors.orange.shade200),
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
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          // 底部固定按鈕（永遠可見）
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
    return _scrollableCenter(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 吉祥物跳動動畫
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.9, end: 1.1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeInOut,
            builder: (context, val, child) =>
                Transform.scale(scale: val, child: child),
            onEnd: () => setState(() {}), // 觸發重建讓動畫循環
            child: _mascot(size: 160, emotion: 'cheer'),
          ),
          const SizedBox(height: 28),
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
      appBar: showBack
          ? AppBar(
              backgroundColor: const Color(0xFFFFF8F0),
              elevation: 0,
              leading: IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.orange,
                ),
                onPressed: _handleBack,
                tooltip: '回上一步',
              ),
            )
          : null,
      // 進度點指示器
      bottomNavigationBar: Container(
        height: 48,
        color: const Color(0xFFFFF8F0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(8, (i) {
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
            child: Text(
              _lines.join(),
              style: const TextStyle(fontSize: 18),
            ),
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
              _buildPage6(),
              _buildPage7(),
            ],
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
