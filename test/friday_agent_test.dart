import 'package:flutter_test/flutter_test.dart';
import 'package:friday_app/features/agent/friday_agent.dart';

const _summary = '''
EYES pkg=com.example nodes=2
- [Button] "Search" [tap] @[0.500,0.300]
- [EditText] "" [tap,edit] @[0.500,0.500]
''';

class _FakeEyes implements AgentEyes {
  const _FakeEyes();

  @override
  Future<String> getSummary({int maxNodes = 15}) async => _summary;
}

class _FakeHands implements AgentHands {
  bool armed = true;
  final taps = <List<double>>[];
  final texts = <String>[];

  @override
  Future<bool> isArmed() async => armed;

  @override
  Future<Map<String, dynamic>> tap(double x, double y) async {
    taps.add([x, y]);
    return {'success': true, 'status': 'SUCCESS'};
  }

  @override
  Future<Map<String, dynamic>> enterText(String text) async {
    texts.add(text);
    return {'success': true, 'status': 'SUCCESS'};
  }
}

class _ScriptModel implements AgentModel {
  final List<String> replies;
  int calls = 0;
  _ScriptModel(this.replies);

  @override
  Future<String> generateRaw({
    required String system,
    required String user,
    int maxTokens = 32,
  }) async {
    return replies[calls++ % replies.length];
  }
}

FridayAgent _agent({
  _FakeHands? hands,
  List<String>? replies,
}) {
  final h = hands ?? _FakeHands();
  return FridayAgent(
    eyes: const _FakeEyes(),
    hands: h,
    model: _ScriptModel(replies ?? const ['DONE']),
  );
}

void main() {
  group('parseCandidates', () {
    test('extracts numbered candidates with fractions', () {
      final items = FridayAgent.parseCandidates(_summary);
      expect(items.length, 2);
      expect(items[0].label, 'Search');
      expect(items[0].canTap, isTrue);
      expect(items[0].fx, 0.5);
      expect(items[0].fy, 0.3);
      expect(items[1].canEdit, isTrue);
    });

    test('skips lines without fractions', () {
      final items = FridayAgent.parseCandidates(
          'EYES_EMPTY: package=x (no readable text/buttons)');
      expect(items, isEmpty);
    });
  });

  group('runGoal', () {
    test('tap then done executes one tap and succeeds', () async {
      final hands = _FakeHands();
      final agent = _agent(hands: hands, replies: const ['TAP 1', 'DONE']);
      final res = await agent.runGoal('tap search');
      expect(res.done, isTrue);
      expect(res.status, 'SUCCESS');
      expect(res.stepsTaken, 1);
      expect(hands.taps, hasLength(1));
      expect(hands.taps.single[0], closeTo(0.5, 1e-9));
      expect(hands.taps.single[1], closeTo(0.3, 1e-9));
    });

    test('type sends text then done succeeds', () async {
      final hands = _FakeHands();
      final agent =
          _agent(hands: hands, replies: const ['TYPE 2 hello', 'DONE']);
      final res = await agent.runGoal('type hello');
      expect(res.done, isTrue);
      expect(hands.texts, ['hello']);
    });

    test('disarmed stops before any action', () async {
      final hands = _FakeHands()..armed = false;
      final agent = _agent(hands: hands, replies: const ['TAP 1', 'DONE']);
      final res = await agent.runGoal('tap search');
      expect(res.done, isFalse);
      expect(res.status, 'DISARMED');
      expect(res.stepsTaken, 0);
      expect(hands.taps, isEmpty);
    });

    test('garbage reply stops with parse failure', () async {
      final hands = _FakeHands();
      final agent = _agent(hands: hands, replies: const ['hello world']);
      final res = await agent.runGoal('tap search');
      expect(res.done, isFalse);
      expect(res.status, 'PARSE_FAILED');
      expect(hands.taps, isEmpty);
    });

    test('out-of-range item stops with parse failure', () async {
      final agent = _agent(replies: const ['TAP 9']);
      final res = await agent.runGoal('tap search');
      expect(res.status, 'PARSE_FAILED');
    });

    test('repeating taps hit max steps', () async {
      final hands = _FakeHands();
      final agent = _agent(hands: hands, replies: const ['TAP 1']);
      final res = await agent.runGoal('tap search', maxSteps: 2);
      expect(res.done, isFalse);
      expect(res.status, 'MAX_STEPS');
      expect(hands.taps, hasLength(2));
    });

    test('handles echoed prompt followed by Decision: TAP 1', () async {
      final hands = _FakeHands();
      final agent = _agent(
        hands: hands,
        replies: const [
          'Goal: tap Search\nScreen buttons:\n[1] "Search" tap\nDecision: TAP 1',
          'DONE',
        ],
      );
      final res = await agent.runGoal('tap Search');
      expect(res.done, isTrue);
      expect(res.status, 'SUCCESS');
      expect(hands.taps, hasLength(1));
    });

    test('does not falsely match verb without number from goal', () async {
      final hands = _FakeHands();
      final agent = _agent(
        hands: hands,
        replies: const [
          'Goal: tap Search\nScreen buttons: [1] "Search" tap\nJust tap Search',
        ],
      );
      final res = await agent.runGoal('tap Search');
      expect(res.done, isFalse);
      expect(res.status, 'PARSE_FAILED');
      expect(hands.taps, isEmpty);
    });

    test('blank goal is rejected without model calls', () async {
      final model = _ScriptModel(const ['DONE']);
      final agent = FridayAgent(
        eyes: _FakeEyes(),
        hands: _FakeHands(),
        model: model,
      );
      final res = await agent.runGoal('  ');
      expect(res.status, 'INVALID_REQUEST');
      expect(model.calls, 0);
    });
  });
}
