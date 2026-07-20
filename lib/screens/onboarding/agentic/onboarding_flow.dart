// Spec: specs/106-onboarding-conversacional-agente/spec.md
//
// Flujo de preguntas del REGISTRO CORTO (State & History Manager): solo
// credenciales — nombre del dueño, celular y clave. Todo lo demás (nombre del
// negocio, tipos, logo, empleados) lo configura la conversación con Vendi
// DESPUÉS de crear la cuenta (Spec 106 reemplaza el flujo F045 de 8 preguntas).
// La completitud de cada pregunta lee los GETTERS del
// OnboardingStepperController (no duplica validación → no diverge de
// canRegister). El reset (undo) limpia el campo SIEMPRE por setter.
import '../onboarding_stepper_controller.dart';

/// Tipo de entrada de una pregunta del agente.
enum QKind { text, pin }

/// Etapa visual del Top Canvas asociada a la pregunta.
enum CanvasStage { datos }

class OnboardingQuestion {
  const OnboardingQuestion({
    required this.id,
    required this.prompt,
    required this.subtitle,
    required this.kind,
    required this.stage,
    required this.isResolved,
    required this.reset,
  });

  final String id;
  final String prompt;
  final String subtitle;
  final QKind kind;
  final CanvasStage stage;

  /// ¿La pregunta ya está contestada? Lee getters del controller.
  final bool Function(OnboardingStepperController c, Set<String> answered)
      isResolved;

  /// Limpia el/los campo(s) de la pregunta vía SETTERS (undo). Nunca
  /// asignación directa — preserva side-effects.
  final void Function(OnboardingStepperController c, Set<String> answered)
      reset;
}

/// Las 3 preguntas del registro corto, en orden.
const List<OnboardingQuestion> kOnboardingQuestions = [
  OnboardingQuestion(
    id: 'owner',
    prompt: '¿Cómo se llama usted?',
    subtitle: '',
    kind: QKind.text,
    stage: CanvasStage.datos,
    isResolved: _ownerResolved,
    reset: _ownerReset,
  ),
  OnboardingQuestion(
    id: 'phone',
    prompt: 'Su número de celular',
    subtitle: 'Lo usará para entrar a VendIA.',
    kind: QKind.text,
    stage: CanvasStage.datos,
    isResolved: _phoneResolved,
    reset: _phoneReset,
  ),
  OnboardingQuestion(
    id: 'pin',
    prompt: 'Cree una clave de 4 a 8 números',
    subtitle: 'La usará cada día para abrir su caja.',
    kind: QKind.pin,
    stage: CanvasStage.datos,
    isResolved: _pinResolved,
    reset: _pinReset,
  ),
];

/// Índice de la primera pregunta NO resuelta (o la última si todo está listo).
int firstUnansweredIndex(OnboardingStepperController c, Set<String> answered) {
  for (var i = 0; i < kOnboardingQuestions.length; i++) {
    if (!kOnboardingQuestions[i].isResolved(c, answered)) return i;
  }
  return kOnboardingQuestions.length - 1;
}

OnboardingQuestion questionById(String id) =>
    kOnboardingQuestions.firstWhere((q) => q.id == id);

// ── Predicados y resets (funciones top-level: const-friendly) ───────────────
bool _ownerResolved(OnboardingStepperController c, Set<String> _) => c.ownerValid;
void _ownerReset(OnboardingStepperController c, Set<String> a) {
  c.setOwnerName('');
  c.setOwnerLastName('');
}

bool _phoneResolved(OnboardingStepperController c, Set<String> _) => c.phoneValid;
void _phoneReset(OnboardingStepperController c, Set<String> a) => c.setPhone('');

bool _pinResolved(OnboardingStepperController c, Set<String> _) =>
    c.pinValid && c.pinConfirmed;
void _pinReset(OnboardingStepperController c, Set<String> a) {
  c.setPin('');
  c.setConfirmPin('');
}
