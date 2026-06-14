// Spec: specs/048-onboarding-video-bg/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vendia_pos/screens/onboarding/agentic/onboarding_agentic_animated_view.dart';
import 'package:vendia_pos/screens/onboarding/onboarding_stepper_controller.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/widgets/sprite_sheet_player.dart';

OnboardingStepperController _ctrl() => OnboardingStepperController(
      apiCall: (_) async => {},
      saveSession: (_) async {},
    );

Widget _wrap(OnboardingStepperController c) => MediaQuery(
      // reduce-motion → sin Ticker, render determinista del fondo.
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(
        home: ChangeNotifierProvider<OnboardingStepperController>.value(
          value: c,
          child: OnboardingAgenticAnimatedView(
            apiOverride: ApiService(AuthService()),
            persistOverride: false,
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() =>
      dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  // Desktop, tablet y mobile — sin afectar la relación de aspecto (cover).
  final sizes = <String, Size>{
    'desktop': const Size(1280, 900),
    'tablet': const Size(834, 1180),
    'mobile': const Size(360, 720),
  };

  sizes.forEach((label, size) {
    testWidgets('video de fondo presente y sin overflow en $label', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final c = _ctrl();
      addTearDown(c.dispose);
      await tester.pumpWidget(_wrap(c));
      await tester.pump();

      // El fondo de video está montado detrás del contenido.
      expect(find.byType(SpriteSheetPlayer), findsOneWidget);
      // El layout no desborda a ningún tamaño.
      expect(tester.takeException(), isNull);
    });
  });
}
