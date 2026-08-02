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
