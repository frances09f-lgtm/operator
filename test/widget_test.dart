import 'package:flutter_test/flutter_test.dart';
import 'package:friday_app/features/assistant/domain/intent_parser.dart';
import 'package:friday_app/features/assistant/presentation/assistant_controller.dart';
import 'package:friday_app/features/assistant/presentation/widgets/assistant_orb.dart';
import 'package:friday_app/main.dart';
import 'assistant_controller_test.dart';

void main() {
  testWidgets('FRIDAY UI renders title, orb, input, and button', (WidgetTester tester) async {
    final llmService = FakeLocalLLMService();
    final intentParser = IntentParser();
    final appLauncher = FakeAppLauncherService();
    final modelManager = FakeModelManager();

    final controller = AssistantController(
      llmService: llmService,
      intentParser: intentParser,
      appLauncher: appLauncher,
      modelManager: modelManager,
      respondingDuration: const Duration(milliseconds: 50),
    );

    await tester.pumpWidget(FridayApp(controller: controller));
    // The orb animates forever, so use discrete pumps instead of pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('FRIDAY'), findsOneWidget);
    expect(find.text('Local AI Assistant'), findsOneWidget);
    expect(find.byType(AssistantOrb), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Local AI Ready'), findsOneWidget);
  });
}
