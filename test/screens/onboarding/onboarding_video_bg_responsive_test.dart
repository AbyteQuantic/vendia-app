// Spec: specs/106-onboarding-conversacional-agente/spec.md (Adenda OS1)
//
// El fondo de video hexagonal (Spec 048) fue reemplazado por la dirección
// OS1 "Her": fondo limpio en gradiente + el símbolo vivo de Vendi (VendiOrb).
// Este test conserva la garantía original: el registro renderiza sin
// overflow en desktop, tablet y mobile — ahora con el orb presente.
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vendia_pos/screens/onboarding/agentic/onboarding_agentic_animated_view.dart';
import 'package:vendia_pos/screens/onboarding/onboarding_stepper_controller.dart';
import 'package:vendia_pos/screens/onboarding/vendi/vendi_orb.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

OnboardingStepperController _ctrl() => OnboardingStepperController(
      apiCall: (_) async => {},
      saveSession: (_) async {},
    );

Widget _wrap(OnboardingStepperController c) => MediaQuery(
      // reduce-motion → sin Ticker de vida, render determinista del orb.
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

  // Desktop, tablet y mobile — el orb escala sin romper el layout.
  final sizes = <String, Size>{
    'desktop': const Size(1280, 900),
    'tablet': const Size(834, 1180),
    'mobile': const Size(360, 720),
  };

  for (final entry in sizes.entries) {
    testWidgets('símbolo de Vendi presente y sin overflow en ${entry.key}',
        (tester) async {
      await tester.binding.setSurfaceSize(entry.value);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final c = _ctrl();
      await tester.pumpWidget(_wrap(c));
      await tester.pump();

      expect(find.byType(VendiOrb), findsOneWidget);
      expect(find.byKey(const Key('vendi_orb')), findsOneWidget);
      // Llegar aquí sin excepción de overflow ES la aserción de layout.
    });
  }
}
