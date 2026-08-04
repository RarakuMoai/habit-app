// 打卡編排器的排程身分與語意機會模型。
//
// home_completion_test 守的是「首頁在第幾毫秒做了什麼」；這裡守的是編排器
// 自己的規則，不需要整棵 widget 樹：
//   - 語意機會：被拒不消耗，後續有效成員可以重試
//   - 排程身分：被撤銷的成員留下的 timer 不得改掛到別人身上
//   - 交付一次就結束，其餘 timer 一律 no-op
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/home/completion_presentation_controller.dart';

/// 收下每一次語意交付：(phase, kind, 送出去的成員 habitKey)。
typedef _Semantic = (CompletionPhase, CompletionKind, String);

/// 依 habitKey 決定接不接受語意，其餘 phase 一律照收。
class _Recorder {
  _Recorder({this.accept = true});

  bool accept;
  final List<_Semantic> semantics = [];
  final List<String> impacts = [];
  final List<CompletionPhase> all = [];

  CompletionDelivery call(
    CompletionPhase phase,
    HomeCompletionEvent event,
    CompletionKind kind,
  ) {
    all.add(phase);
    if (phase == CompletionPhase.impact) impacts.add(event.habitKey);
    if (phase == CompletionPhase.speak ||
        phase == CompletionPhase.milestoneHandoff) {
      if (!accept) return CompletionDelivery.rejected;
      semantics.add((phase, kind, event.habitKey));
    }
    return CompletionDelivery.delivered;
  }
}

CompletionPresentationController _controller(_Recorder recorder) =>
    CompletionPresentationController(onPhase: recorder.call);

HomeCompletionEvent _start(
  CompletionPresentationController c,
  String key, {
  bool crossedHalf = false,
  int doneCount = 1,
}) => c.start(
  habitKey: key,
  dayRevision: 1,
  crossedHalf: crossedHalf,
  doneCount: doneCount,
  reduceMotion: false,
);

/// 一個成員從自己被建立算起，到它那次語意機會為止的間隔。
Duration _semanticDelayFor({required bool isLead}) => isLead
    ? CompletionPresentationController.kSpeakDelay
    : CompletionPresentationController.kImpactDelay +
          CompletionPresentationController.kMilestoneHandoffAfterImpact;

void main() {
  group('語意機會：被拒不消耗資格', () {
    test('領頭被拒之後，跨過門檻的後續成員補送一次 half', () {
      fakeAsync((clock) {
        final rec = _Recorder(accept: false);
        final c = _controller(rec);
        addTearDown(c.dispose);

        _start(c, 'A');
        clock.elapse(CompletionPresentationController.kSpeakDelay);
        expect(rec.semantics, isEmpty, reason: '領頭那一次被拒了');

        // 之後加入的有效成員讓弧線跨過門檻：它必須拿得到新的機會。
        rec.accept = true;
        _start(c, 'C', crossedHalf: true, doneCount: 2);
        clock.elapse(_semanticDelayFor(isLead: false));

        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.half, 'C'),
        ], reason: '被拒不得吃掉資格；這條弧線還沒開過口，所以這是它的第一次開口（直接整合成里程碑）');

        clock.elapse(const Duration(seconds: 5));
        expect(rec.semantics, hasLength(1), reason: '交付之後其餘 timer 一律 no-op');
      });
    });

    test('領頭被拒之後，沒跨門檻的後續成員仍能重試一般語意', () {
      fakeAsync((clock) {
        final rec = _Recorder(accept: false);
        final c = _controller(rec);
        addTearDown(c.dispose);

        _start(c, 'A');
        clock.elapse(CompletionPresentationController.kSpeakDelay);
        expect(rec.semantics, isEmpty);

        rec.accept = true;
        _start(c, 'B', doneCount: 2);
        clock.elapse(_semanticDelayFor(isLead: false));

        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.ordinary, 'B'),
        ], reason: '仍然是「這條弧線第一次開口」，不是補送里程碑');

        clock.elapse(const Duration(seconds: 5));
        expect(rec.semantics, hasLength(1));
      });
    });

    test('第一次就以 half 交付時，一般語意與里程碑同時算完成', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        _start(c, 'A', crossedHalf: true, doneCount: 2);
        clock.elapse(CompletionPresentationController.kSpeakDelay);
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.half, 'A'),
        ]);

        // 之後再有成員跨門檻也不補第二次。
        _start(c, 'B', crossedHalf: true, doneCount: 3);
        clock.elapse(const Duration(seconds: 5));
        expect(rec.semantics, hasLength(1), reason: 'half 交付過就不再補送');
      });
    });

    test('一般語意成功後才跨門檻：只補一次 half', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        _start(c, 'A');
        clock.elapse(CompletionPresentationController.kSpeakDelay);
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.ordinary, 'A'),
        ]);

        _start(c, 'B', crossedHalf: true, doneCount: 2);
        _start(c, 'C', crossedHalf: true, doneCount: 3);
        clock.elapse(const Duration(seconds: 5));

        expect(
          rec.semantics.where((s) => s.$1 == CompletionPhase.milestoneHandoff),
          hasLength(1),
          reason: '兩個半程成員只補一次里程碑',
        );
      });
    });
  });

  group('排程身分：被撤銷的 timer 不得冒用別人', () {
    test('撤銷 B 之後，B 的里程碑 timer 不得改掛到 C 身上', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        _start(c, 'A'); // t=0
        clock.elapse(CompletionPresentationController.kSpeakDelay); // t=470
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.ordinary, 'A'),
        ]);

        clock.elapse(const Duration(milliseconds: 30)); // t=500
        final b = _start(c, 'B', crossedHalf: true, doneCount: 2);

        clock.elapse(const Duration(milliseconds: 20)); // t=520
        expect(c.cancelEvent(b.id), CompletionCancelOutcome.arcSurvives);
        // Home 在資料寫完之後回報權威進度：撤銷 B 讓它掉回門檻以下。
        c.syncAboveThreshold(false);

        clock.elapse(const Duration(milliseconds: 160)); // t=680
        _start(c, 'C', crossedHalf: true, doneCount: 2);

        // B 原本的機會落在 t=970，C 的衝擊點在 t=980。
        clock.elapse(const Duration(milliseconds: 295)); // t=975
        expect(
          rec.semantics.where((s) => s.$1 == CompletionPhase.milestoneHandoff),
          isEmpty,
          reason: 'B 已經被撤銷，它的 timer 必須作廢，不得改掛到 C',
        );
        expect(rec.impacts, isNot(contains('C')), reason: 'C 的衝擊點都還沒到');

        clock.elapse(const Duration(seconds: 2));
        expect(rec.impacts, contains('C'), reason: 'C 自己的衝擊點照發');
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.ordinary, 'A'),
          (CompletionPhase.milestoneHandoff, CompletionKind.half, 'C'),
        ], reason: '里程碑只能由 C 自己的 timer、在 C 的衝擊點之後交付一次');
      });
    });

    test('B 沒被撤銷時由 B 交付，C 的 timer 不重複', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        _start(c, 'A');
        clock.elapse(CompletionPresentationController.kSpeakDelay);
        clock.elapse(const Duration(milliseconds: 30));
        _start(c, 'B', crossedHalf: true, doneCount: 2);
        clock.elapse(const Duration(milliseconds: 180)); // t=680
        _start(c, 'C', crossedHalf: true, doneCount: 3);
        clock.elapse(const Duration(seconds: 3));

        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.ordinary, 'A'),
          (CompletionPhase.milestoneHandoff, CompletionKind.half, 'B'),
        ], reason: 'B 是先到的那個機會；C 的 timer 不得再補一次');
      });
    });

    test('撤銷 B 且沒有後續半程成員：弧線降回一般完成', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        _start(c, 'A');
        clock.elapse(CompletionPresentationController.kSpeakDelay);
        clock.elapse(const Duration(milliseconds: 30));
        final b = _start(c, 'B', crossedHalf: true, doneCount: 2);
        clock.elapse(const Duration(milliseconds: 20));
        c.cancelEvent(b.id);
        clock.elapse(const Duration(seconds: 3));

        expect(
          rec.semantics.where((s) => s.$1 == CompletionPhase.milestoneHandoff),
          isEmpty,
          reason: '半程成員沒了，弧線就不該再補里程碑',
        );
      });
    });

    test('領頭被撤銷：弧線收尾仍由仍有效的成員送出', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        final a = _start(c, 'A');
        clock.elapse(const Duration(milliseconds: 40));
        _start(c, 'B', doneCount: 2);
        clock.elapse(const Duration(milliseconds: 60));
        expect(c.cancelEvent(a.id), CompletionCancelOutcome.arcSurvives);

        clock.elapse(const Duration(seconds: 4));
        expect(
          rec.all,
          contains(CompletionPhase.recover),
          reason: '整條弧線共用的收尾不該因為領頭被撤銷就消失',
        );
        expect(rec.all, contains(CompletionPhase.quiet));
        expect(rec.impacts, isNot(contains('A')), reason: '但被撤銷那一件自己的衝擊點必須作廢');
        expect(rec.impacts, contains('B'));
      });
    });

    test('rejected B、有效 C 接手：只能由 C 自己的 timer 在 C 衝擊點之後交付', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        _start(c, 'A');
        clock.elapse(CompletionPresentationController.kSpeakDelay);
        rec.semantics.clear();

        // B 與 C 都要落在領頭的 700ms 合併視窗內，才是同一條弧線。
        rec.accept = false;
        clock.elapse(const Duration(milliseconds: 30)); // t=500
        _start(c, 'B', crossedHalf: true, doneCount: 2);
        clock.elapse(const Duration(milliseconds: 180)); // t=680
        _start(c, 'C', crossedHalf: true, doneCount: 3);

        clock.elapse(const Duration(milliseconds: 290)); // t=970：B 的機會
        expect(rec.semantics, isEmpty, reason: 'B 那一次被拒了');

        rec.accept = true;
        final impactsBeforeC = rec.impacts.length;
        clock.elapse(const Duration(milliseconds: 15)); // t=985：C 的衝擊點
        expect(
          rec.impacts.length,
          greaterThan(impactsBeforeC),
          reason: 'C 自己的衝擊點要先發生',
        );
        expect(rec.semantics, isEmpty, reason: '語意不得早於 C 的衝擊點');

        clock.elapse(const Duration(milliseconds: 200)); // t=1185：C 的機會
        expect(rec.semantics, [
          (CompletionPhase.milestoneHandoff, CompletionKind.half, 'C'),
        ]);

        clock.elapse(const Duration(seconds: 4));
        expect(rec.semantics, hasLength(1));
      });
    });
  });

  group('門檻世代', () {
    test('尚未 impact 的跨越不得被別人的機會借去用', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        _start(c, 'A'); // t=0
        clock.elapse(CompletionPresentationController.kSpeakDelay); // t=470
        _start(c, 'B'); // t=470，一般完成
        clock.elapse(const Duration(milliseconds: 180)); // t=650
        _start(c, 'C', crossedHalf: true, doneCount: 3);

        // B 的機會在 t=940；C 的衝擊點在 t=950。
        clock.elapse(const Duration(milliseconds: 295)); // t=945
        expect(
          rec.semantics.where((s) => s.$2 == CompletionKind.half),
          isEmpty,
          reason: 'C 還沒演到自己的衝擊點，這次跨越還不能被講出來',
        );
        expect(rec.impacts, isNot(contains('C')));

        clock.elapse(const Duration(seconds: 2));
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.ordinary, 'A'),
          (CompletionPhase.milestoneHandoff, CompletionKind.half, 'C'),
        ], reason: '門檻語意只能由與這次跨越有因果關係的機會交付');
      });
    });

    test('交付過的跨越被撤銷之後，重新跨過去是新的一次', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        _start(c, 'A'); // t=0
        clock.elapse(const Duration(milliseconds: 100));
        final b = _start(c, 'B', crossedHalf: true, doneCount: 2); // t=100
        clock.elapse(const Duration(milliseconds: 370)); // t=470
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.half, 'A'),
        ], reason: 'B 已經 impact，領頭那一拍直接整合成 half');

        clock.elapse(const Duration(milliseconds: 10)); // t=480
        expect(c.cancelEvent(b.id), CompletionCancelOutcome.arcSurvives);
        c.syncAboveThreshold(false); // 進度掉回門檻以下
        clock.elapse(const Duration(milliseconds: 20)); // t=500
        _start(c, 'C', crossedHalf: true, doneCount: 2);
        clock.elapse(const Duration(seconds: 3));

        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.half, 'A'),
          (CompletionPhase.milestoneHandoff, CompletionKind.half, 'C'),
        ], reason: '撤銷讓第一次跨越失效；重新跨過去可以再交付一次');
      });
    });

    test('Home 回報進度跌回門檻以下：正在進行的跨越當場失效', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        _start(c, 'A');
        clock.elapse(CompletionPresentationController.kSpeakDelay);
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.ordinary, 'A'),
        ]);

        clock.elapse(const Duration(milliseconds: 30));
        _start(c, 'B', crossedHalf: true, doneCount: 2);
        // 使用者撤銷了一件**不屬於這條弧線**的舊習慣，進度掉回門檻以下。
        c.syncAboveThreshold(false);
        clock.elapse(const Duration(seconds: 3));

        expect(
          rec.semantics.where((s) => s.$2 == CompletionKind.half),
          isEmpty,
          reason: '門檻的真相在 Home 的進度，不在成員身上的歷史旗標',
        );
      });
    });

    test('已經在門檻之上時再完成一件，不算新的一次跨越', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        _start(c, 'A', crossedHalf: true, doneCount: 2);
        clock.elapse(CompletionPresentationController.kSpeakDelay);
        expect(rec.semantics, hasLength(1));

        // 同一次跨越還有效時再加一個「跨越」成員：不建立新的世代。
        _start(c, 'B', crossedHalf: true, doneCount: 3);
        clock.elapse(const Duration(seconds: 3));
        expect(rec.semantics, hasLength(1), reason: '同一次跨越只講一次');
      });
    });

    test('被撤銷的成員留下的 timer 不得替下一次跨越交付', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        _start(c, 'A');
        clock.elapse(CompletionPresentationController.kSpeakDelay); // t=470
        clock.elapse(const Duration(milliseconds: 30)); // t=500
        final b = _start(c, 'B', crossedHalf: true, doneCount: 2);
        clock.elapse(const Duration(milliseconds: 20)); // t=520
        c.cancelEvent(b.id);
        c.syncAboveThreshold(false); // 進度掉回門檻以下
        clock.elapse(const Duration(milliseconds: 160)); // t=680
        _start(c, 'C', crossedHalf: true, doneCount: 2);

        // B 的機會在 t=970，C 的衝擊點在 t=980。
        clock.elapse(const Duration(milliseconds: 295)); // t=975
        expect(
          rec.semantics.where((s) => s.$2 == CompletionKind.half),
          isEmpty,
          reason: 'B 已經被撤銷，它的 timer 不得替 C 的那一次交付',
        );

        clock.elapse(const Duration(seconds: 2));
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.ordinary, 'A'),
          (CompletionPhase.milestoneHandoff, CompletionKind.half, 'C'),
        ]);
      });
    });

    test('被拒的門檻語意可以由同一次跨越的後續機會重試', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        _start(c, 'A');
        clock.elapse(CompletionPresentationController.kSpeakDelay); // ordinary
        rec.semantics.clear();

        rec.accept = false;
        clock.elapse(const Duration(milliseconds: 30)); // t=500
        _start(c, 'B', crossedHalf: true, doneCount: 2);
        clock.elapse(const Duration(milliseconds: 180)); // t=680
        _start(c, 'C', doneCount: 3); // 一般完成，只是提供另一次機會

        clock.elapse(const Duration(milliseconds: 290)); // t=970：B 的機會被拒
        expect(rec.semantics, isEmpty);

        rec.accept = true;
        clock.elapse(const Duration(seconds: 3)); // C 的機會 t=1150
        expect(rec.semantics, [
          (CompletionPhase.milestoneHandoff, CompletionKind.half, 'C'),
        ], reason: '被拒不消耗這一次跨越的交付資格');
      });
    });
  });

  group('撤銷門檻來源之後', () {
    test('進度仍在門檻之上：由已 impact 的有效成員在自己的機會交付一次', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        // 另有一件早就完成的舊習慣不在這條弧線裡。C 把 1/4 推到 2/4。
        final cEvent = _start(c, 'C', crossedHalf: true, doneCount: 2);
        clock.elapse(const Duration(milliseconds: 10));
        _start(c, 'D', doneCount: 3); // t=10，3/4

        // C 的衝擊點 t=300、D 的 t=310。兩個機會分別在 t=470 與 t=480。
        clock.elapse(const Duration(milliseconds: 310)); // t=320
        expect(rec.impacts, ['C', 'D']);
        expect(rec.semantics, isEmpty);

        expect(c.cancelEvent(cEvent.id), CompletionCancelOutcome.arcSurvives);
        // Home 寫完資料後回報：撤銷 C 之後仍然是 2/4，門檻沒有掉。
        c.syncAboveThreshold(true);

        clock.elapse(const Duration(milliseconds: 200)); // t=520
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.half, 'D'),
        ], reason: '撤銷 C 沒有撤銷使用者看得見的進度；D 已經 impact，要能接手一次');

        clock.elapse(const Duration(seconds: 4));
        expect(rec.semantics, hasLength(1), reason: '只交付一次');
      });
    });

    test('撤銷來源時後續成員還沒 impact：不得立即交付，要等它自己的因果鏈', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        final cEvent = _start(c, 'C', crossedHalf: true, doneCount: 2);
        clock.elapse(const Duration(milliseconds: 200)); // t=200，D 加入
        _start(c, 'D', doneCount: 3); // 衝擊點 t=500，機會 t=670

        clock.elapse(const Duration(milliseconds: 105)); // t=305：C 已 impact
        expect(rec.impacts, ['C']);
        c.cancelEvent(cEvent.id);
        c.syncAboveThreshold(true);

        // C 自己的機會落在 t=470：它已經被撤銷，不得交付。
        clock.elapse(const Duration(milliseconds: 175)); // t=480
        expect(rec.semantics, isEmpty, reason: 'D 還沒演到自己的衝擊點，這一次跨越還不能被講出來');
        expect(rec.impacts, isNot(contains('D')));

        clock.elapse(const Duration(milliseconds: 30)); // t=510：D 的衝擊點
        expect(rec.impacts, contains('D'));
        expect(rec.semantics, isEmpty, reason: '衝擊點那一拍還不是語意拍');

        clock.elapse(const Duration(seconds: 3)); // D 的機會 t=670
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.half, 'D'),
        ], reason: '只能由 D 自己的機會交付，不是沿用 C 的 timer');
      });
    });

    test('撤銷來源後進度掉回門檻以下：這一次跨越失效', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        final cEvent = _start(c, 'C', crossedHalf: true, doneCount: 2);
        clock.elapse(const Duration(milliseconds: 10));
        _start(c, 'D', doneCount: 3);
        clock.elapse(const Duration(milliseconds: 310)); // t=320

        c.cancelEvent(cEvent.id);
        c.syncAboveThreshold(false); // 這次撤銷真的讓進度掉下去了

        clock.elapse(const Duration(seconds: 4));
        expect(
          rec.semantics.where((s) => s.$2 == CompletionKind.half),
          isEmpty,
          reason: '門檻不成立就不該講里程碑',
        );
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.ordinary, 'D'),
        ], reason: '降級成一般完成，仍然由有效成員講一次');
      });
    });

    test('已經交付過的跨越：撤銷來源但門檻仍成立，不得重播', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        final cEvent = _start(c, 'C', crossedHalf: true, doneCount: 2);
        clock.elapse(const Duration(milliseconds: 10));
        _start(c, 'D', doneCount: 3);
        clock.elapse(CompletionPresentationController.kSpeakDelay); // t=470
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.half, 'C'),
        ]);

        c.cancelEvent(cEvent.id);
        c.syncAboveThreshold(true); // 仍在門檻之上
        clock.elapse(const Duration(seconds: 4));

        expect(rec.semantics, hasLength(1), reason: '這一次跨越已經講過了，不重播');
      });
    });

    test('掉回門檻以下再重新跨越：建立新的一次，可再交付一次', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        // D 讓這條弧線在撤銷 C 之後仍然活著，才測得到「同一條弧線裡
        // 掉下去再跨回來」。
        final cEvent = _start(c, 'C', crossedHalf: true, doneCount: 2);
        clock.elapse(const Duration(milliseconds: 10));
        _start(c, 'D', doneCount: 3);
        clock.elapse(const Duration(milliseconds: 460)); // t=470
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.half, 'C'),
        ]);

        c.cancelEvent(cEvent.id);
        c.syncAboveThreshold(false); // 進度真的掉回門檻以下
        clock.elapse(const Duration(milliseconds: 30)); // t=500
        _start(c, 'E', crossedHalf: true, doneCount: 2); // 重新跨越

        clock.elapse(const Duration(seconds: 4));
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.half, 'C'),
          (CompletionPhase.milestoneHandoff, CompletionKind.half, 'E'),
        ], reason: '新的一次跨越可以再講一次');
      });
    });

    test('撤銷來源後整條弧線結束：跨越仍然 pending，由新弧線的有資格成員交付一次', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        final cEvent = _start(c, 'C', crossedHalf: true, doneCount: 2);
        clock.elapse(const Duration(milliseconds: 305)); // C 已 impact
        c.cancelEvent(cEvent.id);
        c.syncAboveThreshold(true); // 別的習慣仍然完成著：門檻沒有掉
        expect(c.arcActive, isFalse, reason: '最後一個成員也沒了，這條弧線就結束了');

        // 新的一條弧線。跨越是**真實進度**的事件，不是這條弧線的屬性：
        // 動作容器沒了不代表那次跨越沒發生，F 又是跨越之後才出現的有資格成員。
        clock.elapse(const Duration(milliseconds: 100)); // t=405
        _start(c, 'F', doneCount: 2); // 衝擊點 t=705，機會 t=875
        clock.elapse(const Duration(milliseconds: 400)); // t=805
        expect(rec.impacts, ['C', 'F']);
        expect(rec.semantics, isEmpty, reason: 'F 還沒走到自己的機會，不得提前把跨越講出去');

        clock.elapse(const Duration(seconds: 4));
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.half, 'F'),
        ], reason: '仍然成立、還沒講過的跨越不得因為動作容器消失就遺失');
      });
    });

    test('跨越還沒建立起點時新弧線的成員：要等自己的衝擊點，不得提前交付', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        // 來源在自己的衝擊點之前就被撤銷：這次跨越還沒有任何因果起點。
        final cEvent = _start(c, 'C', crossedHalf: true, doneCount: 2);
        clock.elapse(const Duration(milliseconds: 100));
        c.cancelEvent(cEvent.id);
        c.syncAboveThreshold(true);
        expect(c.arcActive, isFalse);

        clock.elapse(const Duration(milliseconds: 100)); // t=200
        _start(c, 'F', doneCount: 2); // 衝擊點 t=500，機會 t=670
        clock.elapse(const Duration(milliseconds: 295)); // t=495
        expect(rec.impacts, isEmpty, reason: '被撤銷的 C 不得留下任何衝擊點');
        expect(rec.semantics, isEmpty);

        clock.elapse(const Duration(seconds: 4));
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.half, 'F'),
        ], reason: '起點改由 F 自己的衝擊點建立，並在 F 自己的機會交付');
      });
    });
  });

  // ── 因果資格：誰有權建立這次跨越的起點 ────────────────────────
  //
  // 起點不再永遠綁在「來源自己的 impact」上：來源可能在自己的衝擊點之前就被
  // 撤銷，那時整次跨越會卡死。改成由**有資格的成員**（來源本身，或跨越之後
  // 才加入的）自己的衝擊點建立。

  group('因果資格', () {
    test('來源在自己的衝擊點之前被撤銷：由後續有效成員建立起點並交付', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        final cEvent = _start(c, 'C', crossedHalf: true, doneCount: 2);
        clock.elapse(const Duration(milliseconds: 10));
        _start(c, 'D', doneCount: 3); // t=10

        clock.elapse(const Duration(milliseconds: 90)); // t=100，C 還沒 impact
        expect(c.cancelEvent(cEvent.id), CompletionCancelOutcome.arcSurvives);
        // 別的習慣仍然完成著：撤銷 C 之後資料還是 2/4。
        c.syncAboveThreshold(true);

        clock.elapse(const Duration(milliseconds: 220)); // t=320
        expect(rec.impacts, ['D'], reason: 'C 的衝擊點必須整拍作廢，不得借用');

        clock.elapse(const Duration(milliseconds: 200)); // t=520
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.half, 'D'),
        ], reason: 'D 自己已 impact、機會也到了，這次跨越必須由它交付');

        clock.elapse(const Duration(seconds: 4));
        expect(rec.semantics, hasLength(1), reason: '只交付一次');
      });
    });

    test('跨越之前就加入的一般成員：來源還沒 impact 時只能講一般完成', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        _start(c, 'B'); // t=0，領頭；機會 t=470
        clock.elapse(const Duration(milliseconds: 180));
        _start(c, 'C', crossedHalf: true, doneCount: 2); // t=180，衝擊點 t=480

        clock.elapse(const Duration(milliseconds: 295)); // t=475
        expect(rec.impacts, isNot(contains('C')));
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.ordinary, 'B'),
        ], reason: 'B 早於這次跨越，不得因為整條弧線後來升級就提前送出 half');

        clock.elapse(const Duration(seconds: 3));
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.ordinary, 'B'),
          (CompletionPhase.milestoneHandoff, CompletionKind.half, 'C'),
        ], reason: '起點成立之後才由有資格的 C 在自己的機會補送');
      });
    });

    test('來源撤銷後門檻真的掉下去：這次跨越失效，後續成員只講一般完成', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        final cEvent = _start(c, 'C', crossedHalf: true, doneCount: 2);
        clock.elapse(const Duration(milliseconds: 10));
        _start(c, 'D', doneCount: 3);

        clock.elapse(const Duration(milliseconds: 90)); // t=100，C 還沒 impact
        c.cancelEvent(cEvent.id);
        c.syncAboveThreshold(false); // 這次撤銷讓進度真的掉回門檻以下

        clock.elapse(const Duration(seconds: 4));
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.ordinary, 'D'),
        ], reason: '門檻不成立就沒有里程碑可講，但一般完成仍然要講一次');
      });
    });
  });

  // ── 擁有權讓出後的補送 ────────────────────────────────────────
  //
  // 被更高優先的狀態（撤銷）擋下的門檻語意只是**被延後**，不是被取消：資料
  // 仍在門檻之上，使用者也已經看過那一勾落下。呼叫端放掉自己的佔用之後，
  // 要把欠的那一次補回來，而且不需要使用者再輸入一次。

  group('擁有權讓出後的補送', () {
    /// 權威 production 形狀：C 跨過門檻、D 跟上，兩件都已 impact，
    /// 之後 C 被撤銷但真實進度仍在門檻之上。
    ({HomeCompletionEvent c, HomeCompletionEvent d}) crossThenUndoSource(
      CompletionPresentationController c,
      FakeAsync clock,
    ) {
      final cEvent = _start(c, 'C', crossedHalf: true, doneCount: 2);
      clock.elapse(const Duration(milliseconds: 10));
      final dEvent = _start(c, 'D', doneCount: 3);
      clock.elapse(const Duration(milliseconds: 310)); // t=320
      c.cancelEvent(cEvent.id);
      c.syncAboveThreshold(true);
      return (c: cEvent, d: dEvent);
    }

    test('被擋下的門檻語意：讓出後由已 impact、機會已到的成員補送一次', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        crossThenUndoSource(c, clock);
        rec.accept = false; // 撤銷正擁有兔咪
        clock.elapse(const Duration(milliseconds: 200)); // t=520 > D 的機會 480
        expect(rec.semantics, isEmpty);
        expect(
          c.pendingSemanticArcIds,
          hasLength(1),
          reason: '被擋下的那一次留下欠條，而且已經有合法 anchor',
        );

        rec.accept = true; // 撤銷的顯示期合法結束
        expect(c.retryPendingSemantic(), isTrue);
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.half, 'D'),
        ], reason: '補送的 anchor 必須是仍有效、已 impact、機會已到的 D');
        expect(rec.impacts, ['C', 'D'], reason: '補送不得重播任何衝擊點');

        expect(c.pendingSemanticArcIds, isEmpty);
        expect(c.retryPendingSemantic(), isFalse, reason: '補送過就不再欠');
        clock.elapse(const Duration(seconds: 4));
        expect(rec.semantics, hasLength(1), reason: '其餘 timer 一律 no-op');
      });
    });

    test('門檻已經跌回以下：讓出時不得補送', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        crossThenUndoSource(c, clock);
        rec.accept = false;
        clock.elapse(const Duration(milliseconds: 200)); // D 的機會被擋下
        c.syncAboveThreshold(false); // 使用者又撤銷了別的，進度掉下去了

        rec.accept = true;
        expect(c.pendingSemanticArcIds, isEmpty);
        expect(c.retryPendingSemantic(), isFalse);
        clock.elapse(const Duration(seconds: 4));
        expect(
          rec.semantics.where((s) => s.$2 == CompletionKind.half),
          isEmpty,
          reason: '門檻不成立的跨越沒有東西可補',
        );
      });
    });

    test('這次跨越已經交付過：讓出時不重播', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        crossThenUndoSource(c, clock);
        clock.elapse(const Duration(milliseconds: 200)); // D 的機會照常交付
        expect(rec.semantics, hasLength(1));

        expect(c.pendingSemanticArcIds, isEmpty);
        expect(c.retryPendingSemantic(), isFalse);
        expect(rec.semantics, hasLength(1), reason: '交付過就不是「欠著」');
      });
    });

    test('anchor 還沒走到自己的機會：補送 no-op，之後到了才有資格', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        final events = crossThenUndoSource(c, clock); // t=320
        rec.accept = false;
        // C 自己的機會在 t=470（C 已被撤銷，整拍作廢）；D 的在 t=480。
        clock.elapse(const Duration(milliseconds: 150)); // t=470
        expect(rec.semantics, isEmpty);
        expect(
          c.pendingSemanticArcIds,
          isEmpty,
          reason: 'D 的機會還沒到，時間線上沒有人補得出來',
        );
        expect(c.retryPendingSemantic(), isFalse);

        clock.elapse(const Duration(milliseconds: 20)); // t=490，D 的機會被擋下
        expect(c.pendingSemanticArcIds, [events.d.arcId]);

        rec.accept = true;
        expect(c.retryPendingSemantic(), isTrue);
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.half, 'D'),
        ]);
      });
    });

    test('補送再次被拒：不消耗資格、不排新的 timer', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        crossThenUndoSource(c, clock);
        rec.accept = false;
        clock.elapse(const Duration(milliseconds: 200));

        expect(c.retryPendingSemantic(), isFalse, reason: '這一次也被拒');
        expect(rec.semantics, isEmpty);
        clock.elapse(const Duration(seconds: 4));
        expect(rec.semantics, isEmpty, reason: '被拒不得排任何自動重試');

        // 弧線的 timer 都收乾淨了，但欠條是**跨越**的狀態不是弧線的：
        // 門檻仍成立、也還沒講過，所以它還在。
        expect(c.presentationActive, isFalse);
        expect(c.pendingSemanticArcIds, hasLength(1));
        expect(c.retryPendingSemantic(), isFalse, reason: '呼叫端仍然擋著');
        expect(rec.semantics, isEmpty);
      });
    });

    test('弧線已經被收掉：跨越仍然補得出來，anchor 不變', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        crossThenUndoSource(c, clock);
        rec.accept = false;
        clock.elapse(const Duration(seconds: 5)); // 整條弧線收乾淨
        expect(c.presentationActive, isFalse);

        rec.accept = true;
        expect(c.retryPendingSemantic(), isTrue);
        expect(rec.semantics, [
          (CompletionPhase.milestoneHandoff, CompletionKind.half, 'D'),
        ], reason: '動作與尾韻早就演完了，這一次是不折不扣的補送');
        expect(rec.impacts, ['C', 'D'], reason: '補送不得重播任何衝擊點');
      });
    });

    test('跨越已經結束：補送安全 no-op', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        crossThenUndoSource(c, clock);
        rec.accept = false;
        clock.elapse(const Duration(milliseconds: 200));
        expect(c.pendingSemanticArcIds, hasLength(1));

        // 跨越自己結束的三條路：門檻跌回、generation 作廢、已經交付。
        c.syncAboveThreshold(false);
        rec.accept = true;
        expect(c.pendingSemanticArcIds, isEmpty);
        expect(c.retryPendingSemantic(), isFalse);
        clock.elapse(const Duration(seconds: 5));
        expect(rec.semantics, isEmpty);
      });
    });

    test('跨日／離開首頁之後：欠條隨 generation 一起作廢', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        crossThenUndoSource(c, clock);
        rec.accept = false;
        clock.elapse(const Duration(milliseconds: 200));
        expect(c.pendingSemanticArcIds, hasLength(1));

        c.invalidate(); // 跨日／換快照／dispose
        rec.accept = true;
        expect(c.pendingSemanticArcIds, isEmpty);
        expect(c.retryPendingSemantic(), isFalse);
        clock.elapse(const Duration(seconds: 4));
        expect(rec.semantics, isEmpty);
      });
    });

    test('呼叫端回報畫面不可用：不留欠條，也補送不出去', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        var playable = true;
        final c = CompletionPresentationController(
          onPhase: rec.call,
          isStillValid: (_) => playable,
        );
        addTearDown(c.dispose);

        crossThenUndoSource(c, clock);
        playable = false;
        clock.elapse(const Duration(milliseconds: 200)); // D 的機會不可播
        expect(rec.semantics, isEmpty);
        expect(
          c.pendingSemanticArcIds,
          isEmpty,
          reason: '「畫面看不到」不是被擁有權擋下，不留欠條',
        );

        playable = true;
        expect(c.retryPendingSemantic(), isFalse);
        expect(rec.semantics, isEmpty);
      });
    });
  });

  // ── 跨越脫離動作弧線 ─────────────────────────────────────────
  //
  // 動作弧線只是 700ms 的 motion grouping；跨越是真實進度的一次事件。
  // 支撐門檻的那一勾可能落在**下一條**弧線裡，上一條弧線根本看不到它。

  group('跨 arc 的跨越', () {
    /// A 開 arc1；C 在視窗關閉前跨過門檻；D 在視窗關閉之後開 arc2。
    ({HomeCompletionEvent a, HomeCompletionEvent c, HomeCompletionEvent d})
    crossThenNewArc(CompletionPresentationController c, FakeAsync clock) {
      final a = _start(c, 'A'); // t=0，arc1 領頭
      clock.elapse(const Duration(milliseconds: 650));
      final crossing = _start(c, 'C', crossedHalf: true, doneCount: 3);
      clock.elapse(const Duration(milliseconds: 70)); // t=720，arc1 視窗已關
      expect(c.arcActive, isFalse, reason: 'arc1 的合併視窗在 700ms 關閉');
      final d = _start(c, 'D', doneCount: 4); // arc2 領頭
      expect(d.arcId, isNot(crossing.arcId), reason: 'D 確實在另一條弧線');
      return (a: a, c: crossing, d: d);
    }

    test('來源在 arc1 pre-impact 被撤銷：由 arc2 的 D 自己的因果鏈交付一次', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        final events = crossThenNewArc(c, clock);
        clock.elapse(const Duration(milliseconds: 80)); // t=800，C 的衝擊點在 950
        expect(
          c.cancelEvent(events.c.id),
          CompletionCancelOutcome.arcSurvives,
          reason: 'A 還在 arc1 裡，共用的那段動作要留著',
        );
        c.syncAboveThreshold(true); // A + D + 舊的完成仍然撐著門檻

        clock.elapse(const Duration(milliseconds: 220)); // t=1020：D 的衝擊點
        expect(rec.impacts, ['A', 'D'], reason: 'C 的衝擊點必須整拍作廢');
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.ordinary, 'A'),
        ], reason: 'arc1 自己的一般語意照發，但這時還輪不到門檻');

        clock.elapse(const Duration(seconds: 4)); // D 的機會 t=1190
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.ordinary, 'A'),
          (CompletionPhase.speak, CompletionKind.half, 'D'),
        ], reason: 'arc1 看不到 D 不該讓跨越遺失；D 有自己的 impact 與機會');
      });
    });

    test('arc2 的成員也在自己的衝擊點之前被撤銷：要等下一個有資格的成員', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        final events = crossThenNewArc(c, clock);
        clock.elapse(const Duration(milliseconds: 80)); // t=800
        c.cancelEvent(events.c.id);
        clock.elapse(const Duration(milliseconds: 50)); // t=850，D 的衝擊點在 1020
        c.cancelEvent(events.d.id);
        c.syncAboveThreshold(true);

        clock.elapse(const Duration(seconds: 2)); // t=2850
        expect(
          rec.semantics.where((s) => s.$2 == CompletionKind.half),
          isEmpty,
          reason: '沒有任何有資格的成員演到自己的衝擊點，這次跨越還不能被講出來',
        );

        // 之後才出現的有資格成員：起點由它自己的衝擊點建立。
        final e = _start(c, 'E', doneCount: 4); // t=2850，arc3
        expect(e.id, greaterThan(events.c.id));
        clock.elapse(const Duration(milliseconds: 295)); // t=3145，E 衝擊點 3150
        expect(
          rec.semantics.where((s) => s.$2 == CompletionKind.half),
          isEmpty,
        );

        clock.elapse(const Duration(seconds: 4)); // E 的機會 t=3320
        expect(rec.semantics, [
          // arc1 自己的一般語意（A 在 t=470）不受影響。
          (CompletionPhase.speak, CompletionKind.ordinary, 'A'),
          (CompletionPhase.speak, CompletionKind.half, 'E'),
        ], reason: '起點與交付都由 E 自己的因果鏈觸發');
      });
    });

    test('跨越交付之後：兩條弧線的收尾都不得再講一次', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        crossThenNewArc(c, clock);
        clock.elapse(const Duration(seconds: 6));
        expect(
          rec.semantics.where((s) => s.$2 == CompletionKind.half),
          hasLength(1),
          reason: '跨越是整個 generation 一次，不是每條弧線一次',
        );
      });
    });
  });

  // ── Sol 第十輪的診斷矩陣（裁決為正確行為，收進來當回歸保護）─────

  group('最小合法序號矩陣', () {
    test('B@0、C@100：C 的衝擊點早於 B 的機會，B 直接整合成 half', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        _start(c, 'B');
        clock.elapse(const Duration(milliseconds: 100));
        _start(c, 'C', crossedHalf: true, doneCount: 2);
        clock.elapse(const Duration(milliseconds: 370)); // t=470

        expect(rec.impacts, ['B', 'C']);
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.half, 'B'),
        ], reason: '起點已經成立，跨越之前加入的成員在自己的機會上整合是合法的');
        clock.elapse(const Duration(seconds: 4));
        expect(rec.semantics, hasLength(1));
      });
    });

    test('B@0、C@180：B 的機會早於 C 的衝擊點，先一般完成再補送', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        _start(c, 'B');
        clock.elapse(const Duration(milliseconds: 180));
        _start(c, 'C', crossedHalf: true, doneCount: 2);
        clock.elapse(const Duration(milliseconds: 295)); // t=475

        expect(rec.impacts, ['B']);
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.ordinary, 'B'),
        ], reason: '起點還沒成立，B 不得提前把跨越講出去');
        clock.elapse(const Duration(seconds: 4));
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.ordinary, 'B'),
          (CompletionPhase.milestoneHandoff, CompletionKind.half, 'C'),
        ]);
      });
    });

    test('多個跨越前的成員：都不能建立起點，但起點成立後可以整合', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        _start(c, 'A'); // 衝擊點 300／機會 470
        clock.elapse(const Duration(milliseconds: 100));
        _start(c, 'B'); // 衝擊點 400／機會 570
        clock.elapse(const Duration(milliseconds: 100));
        _start(c, 'C', crossedHalf: true, doneCount: 3); // 衝擊點 500／機會 670

        clock.elapse(const Duration(milliseconds: 275)); // t=475，C 還沒 impact
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.ordinary, 'A'),
        ]);

        clock.elapse(const Duration(milliseconds: 100)); // t=575
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.ordinary, 'A'),
          (CompletionPhase.milestoneHandoff, CompletionKind.half, 'B'),
        ]);
        clock.elapse(const Duration(seconds: 4));
        expect(rec.semantics, hasLength(2), reason: 'C 的機會不得再補一次');
      });
    });
  });

  group('補送的邊界矩陣', () {
    test('obsolete 不留欠條，之後的成員仍有全新的機會', () {
      fakeAsync((clock) {
        var attempts = 0;
        final semantics = <_Semantic>[];
        final c = CompletionPresentationController(
          onPhase: (phase, event, kind) {
            if (phase != CompletionPhase.speak &&
                phase != CompletionPhase.milestoneHandoff) {
              return CompletionDelivery.delivered;
            }
            attempts++;
            if (attempts == 1) return CompletionDelivery.obsolete;
            semantics.add((phase, kind, event.habitKey));
            return CompletionDelivery.delivered;
          },
        );
        addTearDown(c.dispose);

        _start(c, 'C', crossedHalf: true, doneCount: 2);
        clock.elapse(CompletionPresentationController.kSpeakDelay);
        expect(c.pendingSemanticArcIds, isEmpty);
        expect(c.retryPendingSemantic(), isFalse);

        _start(c, 'D', doneCount: 3);
        clock.elapse(_semanticDelayFor(isLead: false));
        expect(semantics, [(CompletionPhase.speak, CompletionKind.half, 'D')]);
      });
    });

    test('欠著的舊跨越不得從門檻跌回／重新跨越的縫隙漏出去', () {
      fakeAsync((clock) {
        final rec = _Recorder(accept: false);
        final c = _controller(rec);
        addTearDown(c.dispose);

        _start(c, 'C', crossedHalf: true, doneCount: 2);
        clock.elapse(CompletionPresentationController.kSpeakDelay);
        expect(c.pendingSemanticArcIds, hasLength(1));

        c.syncAboveThreshold(false);
        expect(c.pendingSemanticArcIds, isEmpty);
        rec.accept = true;
        _start(c, 'D', crossedHalf: true, doneCount: 2);
        expect(c.retryPendingSemantic(), isFalse, reason: '新的跨越不繼承舊欠條');
        clock.elapse(_semanticDelayFor(isLead: false));
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.half, 'D'),
        ]);
      });
    });
  });

  // ── 交付之後的弧線分界 ──────────────────────────────────────
  //
  // 跨越還欠著時可以跨 arc 找 anchor；**一旦講出去**，它就只是實際交付它的
  // 那一條弧線的語意。門檻仍然成立不代表使用者接下來的每一次完成都是
  // 「又過半了」——那是一次全新的普通完成，該有自己的 completedOne。

  group('交付之後的弧線分界', () {
    test('half 在 arc1 交付後，全新的 arc2 仍然有自己的一般完成', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        _start(c, 'C', crossedHalf: true, doneCount: 3);
        clock.elapse(CompletionPresentationController.kSpeakDelay);
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.half, 'C'),
        ]);

        clock.elapse(const Duration(seconds: 4));
        expect(c.presentationActive, isFalse, reason: 'arc1 已經完整結束');

        _start(c, 'D', doneCount: 4);
        clock.elapse(CompletionPresentationController.kSpeakDelay);
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.half, 'C'),
          (CompletionPhase.speak, CompletionKind.ordinary, 'D'),
        ], reason: '講過的跨越不是之後每一條弧線的語意');

        clock.elapse(const Duration(seconds: 4));
        expect(
          rec.semantics.where((s) => s.$2 == CompletionKind.half),
          hasLength(1),
          reason: '不得重播 halfDone',
        );
      });
    });

    test('同一條弧線裡 half 已經涵蓋一般完成：不再補 completedOne', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        _start(c, 'C', crossedHalf: true, doneCount: 3); // t=0，arc1 領頭
        clock.elapse(const Duration(milliseconds: 100));
        _start(c, 'D', doneCount: 4); // t=100，同一條弧線
        clock.elapse(const Duration(seconds: 4));

        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.half, 'C'),
        ], reason: '里程碑本來就涵蓋一般完成，同一條弧線不得再講一次');
      });
    });

    test('交付之後門檻掉回以下再重新跨越：新的一次仍然講 half', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        _start(c, 'C', crossedHalf: true, doneCount: 3);
        clock.elapse(const Duration(seconds: 4));
        expect(rec.semantics, hasLength(1));

        c.syncAboveThreshold(false);
        expect(c.debugPendingCandidateCount, 0, reason: '失效的跨越整份回收');

        _start(c, 'E', crossedHalf: true, doneCount: 3);
        clock.elapse(const Duration(seconds: 4));
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.half, 'C'),
          (CompletionPhase.speak, CompletionKind.half, 'E'),
        ], reason: '重新跨越是新的一次');
      });
    });
  });

  // ── 語意退場與動作回收解耦 ──────────────────────────────────
  //
  // 動作弧線被 `_sweep()` 回收之後，那一件仍然可能是還欠著的跨越的合法
  // anchor。但它一旦被撤銷，就必須當場從帳本退場——不能因為「找不到弧線」
  // 就讓它繼續當 payload。

  group('語意退場與動作回收解耦', () {
    /// C 跨過門檻、D／E 跟上，全部 impact 且走過自己的機會（都被擋下），
    /// 然後所有動作弧線自然收乾淨。
    ({HomeCompletionEvent c, HomeCompletionEvent d, HomeCompletionEvent e})
    pendingAfterSweep(CompletionPresentationController c, FakeAsync clock) {
      final source = _start(c, 'C', crossedHalf: true, doneCount: 3);
      clock.elapse(const Duration(milliseconds: 10));
      final d = _start(c, 'D', doneCount: 4);
      clock.elapse(const Duration(milliseconds: 10));
      final e = _start(c, 'E', doneCount: 5);
      clock.elapse(const Duration(milliseconds: 300));
      expect(c.cancelEvent(source.id), CompletionCancelOutcome.arcSurvives);
      c.syncAboveThreshold(true); // 其他早就完成的習慣仍然撐著門檻
      clock.elapse(const Duration(seconds: 4));
      expect(c.presentationActive, isFalse, reason: '動作弧線已經全部回收');
      return (c: source, d: d, e: e);
    }

    test('弧線已回收後撤銷候選：它立刻退場，補送也不得選它', () {
      fakeAsync((clock) {
        final rec = _Recorder(accept: false);
        final c = _controller(rec);
        addTearDown(c.dispose);

        final events = pendingAfterSweep(c, clock);
        expect(c.pendingSemanticArcIds, [events.d.arcId]);
        expect(c.debugPendingCandidateCount, 2, reason: 'C 撤銷時已經退場');

        // 動作弧線早就不在了，但 Home 仍然握著這一件的事件身分。
        expect(c.cancelEvent(events.d.id), CompletionCancelOutcome.unknown);
        expect(c.cancelEvent(events.e.id), CompletionCancelOutcome.unknown);
        c.syncAboveThreshold(true);
        rec.accept = true;

        expect(c.debugPendingCandidateCount, 0);
        expect(c.pendingSemanticArcIds, isEmpty);
        expect(c.retryPendingSemantic(), isFalse);
        expect(rec.semantics, isEmpty, reason: '被撤銷的習慣絕不能被當成補送的 payload');
      });
    });

    test('撤銷最早的候選：補送改用下一個仍然有效的合法 anchor', () {
      fakeAsync((clock) {
        final rec = _Recorder(accept: false);
        final c = _controller(rec);
        addTearDown(c.dispose);

        final events = pendingAfterSweep(c, clock);
        expect(c.cancelEvent(events.d.id), CompletionCancelOutcome.unknown);
        c.syncAboveThreshold(true);
        rec.accept = true;

        expect(c.debugPendingCandidateCount, 1);
        expect(c.retryPendingSemantic(), isTrue);
        expect(rec.semantics, [
          (CompletionPhase.milestoneHandoff, CompletionKind.half, 'E'),
        ], reason: 'D 已經被撤銷，最早仍有效的合法 anchor 是 E');
        expect(rec.impacts, ['C', 'D', 'E'], reason: '補送不得重播任何衝擊點');
      });
    });

    test('反覆新弧線／回收／撤銷／重做：帳本不會無界成長，也不留 stale anchor', () {
      fakeAsync((clock) {
        final rec = _Recorder(accept: false);
        final c = _controller(rec);
        addTearDown(c.dispose);

        _start(c, 'C', crossedHalf: true, doneCount: 3);
        clock.elapse(const Duration(seconds: 4));

        var peak = 0;
        for (var i = 0; i < 8; i++) {
          final event = _start(c, 'H$i', doneCount: 4);
          clock.elapse(const Duration(seconds: 4)); // 這一條弧線自然收乾淨
          expect(c.presentationActive, isFalse);
          peak = peak > c.debugPendingCandidateCount
              ? peak
              : c.debugPendingCandidateCount;
          expect(c.cancelEvent(event.id), CompletionCancelOutcome.unknown);
          c.syncAboveThreshold(true);
        }

        expect(peak, lessThanOrEqualTo(2), reason: '每一輪都退場，帳本不會累積');
        expect(
          c.debugPendingCandidateCount,
          1,
          reason: '八件都撤銷了，只剩下從來沒被撤銷的來源 C',
        );

        // 補送用的是仍然有效的 C，不是任何一個已經退場的 H。
        rec.accept = true;
        expect(c.retryPendingSemantic(), isTrue);
        expect(rec.semantics, [
          (CompletionPhase.milestoneHandoff, CompletionKind.half, 'C'),
        ], reason: '被撤銷的成員全部退場，不得留下 stale anchor');
      });
    });

    test('generation 作廢與門檻跌回：帳本整份回收', () {
      fakeAsync((clock) {
        final rec = _Recorder(accept: false);
        final c = _controller(rec);
        addTearDown(c.dispose);

        pendingAfterSweep(c, clock);
        expect(c.debugPendingCandidateCount, 2);
        c.syncAboveThreshold(false);
        expect(c.debugPendingCandidateCount, 0);

        rec.accept = true;
        _start(c, 'F', crossedHalf: true, doneCount: 3);
        clock.elapse(const Duration(seconds: 4));
        expect(c.debugPendingCandidateCount, 0, reason: '交付之後也整份回收');

        // 門檻真的掉回去之後再跨一次：這才是新的一次跨越，帳本重新開始收。
        c.syncAboveThreshold(false);
        _start(c, 'G', crossedHalf: true, doneCount: 3);
        expect(c.debugPendingCandidateCount, greaterThan(0));
        c.invalidate();
        expect(c.debugPendingCandidateCount, 0, reason: 'generation 作廢清帳');
      });
    });
  });

  group('失效的機會不得取得資格', () {
    test('跨日／離開首頁之後的 timer 一律不交付', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        final c = _controller(rec);
        addTearDown(c.dispose);

        _start(c, 'A');
        c.invalidate();
        clock.elapse(const Duration(seconds: 5));
        expect(rec.semantics, isEmpty);
        expect(rec.all, isNot(contains(CompletionPhase.recover)));
      });
    });

    test('呼叫端回報畫面不可用時不消耗資格', () {
      fakeAsync((clock) {
        final rec = _Recorder();
        var playable = false;
        final c = CompletionPresentationController(
          onPhase: rec.call,
          isStillValid: (_) => playable,
        );
        addTearDown(c.dispose);

        _start(c, 'A');
        clock.elapse(CompletionPresentationController.kSpeakDelay);
        expect(rec.semantics, isEmpty);

        playable = true;
        _start(c, 'B', crossedHalf: true, doneCount: 2);
        clock.elapse(_semanticDelayFor(isLead: false));
        expect(rec.semantics, [
          (CompletionPhase.speak, CompletionKind.half, 'B'),
        ], reason: '不可播不等於交付過；弧線還沒開過口，所以仍是第一次開口');
      });
    });
  });
}
