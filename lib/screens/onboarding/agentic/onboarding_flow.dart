// Spec: specs/045-onboarding-agentic/agentic_onboarding_animation_spec.md
//
// Flujo de preguntas (State & History Manager): UNA pregunta a la vez, con
// SKIP de las ya resueltas por la IA. La completitud de cada pregunta lee los
// GETTERS del OnboardingStepperController (no duplica validación → no diverge
// de canRegister). El reset (undo) limpia el campo SIEMPRE por setter.
import '../onboarding_stepper_controller.dart';

/// Tipo de entrada de una pregunta del agente.
enum QKind { text, pin, typeChips, branchChips, logoChips, employeeChips }

/// Etapa visual del Top Canvas asociada a la pregunta.
enum CanvasStage { datos, categoria, logo }

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

  /// ¿La pregunta ya está contestada? Lee getters del controller (datos
  /// tecleados o llenados por la IA) o el set [answered] (chips sí/no).
  final bool Function(OnboardingStepperController c, Set<String> answered)
      isResolved;

  /// Limpia el/los campo(s) de la pregunta vía SETTERS (undo) y la saca de
  /// [answered]. Nunca asignación directa — preserva side-effects.
  final void Function(OnboardingStepperController c, Set<String> answered)
      reset;
}

/// Las 8 preguntas en orden. El orquestador avanza a la primera no resuelta.
const List<OnboardingQuestion> kOnboardingQuestions = [
  OnboardingQuestion(
    id: 'owner',
    prompt: '¿Cómo se llama usted?',
    subtitle: 'Su nombre y apellido.',
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
  OnboardingQuestion(
    id: 'negocio',
    prompt: '¿Cómo se llama su negocio?',
    subtitle: 'Y en qué dirección queda.',
    kind: QKind.text,
    stage: CanvasStage.datos,
    isResolved: _negocioResolved,
    reset: _negocioReset,
  ),
  OnboardingQuestion(
    id: 'tipo',
    prompt: '¿Qué vende principalmente?',
    subtitle: 'Toque la opción que más se parezca.',
    kind: QKind.typeChips,
    stage: CanvasStage.categoria,
    isResolved: _tipoResolved,
    reset: _tipoReset,
  ),
  OnboardingQuestion(
    id: 'local',
    prompt: '¿Tiene más de un local?',
    subtitle: '',
    kind: QKind.branchChips,
    stage: CanvasStage.categoria,
    isResolved: _localResolved,
    reset: _localReset,
  ),
  OnboardingQuestion(
    id: 'logo',
    prompt: 'Pongámosle cara a su negocio',
    subtitle: 'Cree un logo con IA o suba el suyo.',
    kind: QKind.logoChips,
    stage: CanvasStage.logo,
    isResolved: _logoResolved,
    reset: _logoReset,
  ),
  OnboardingQuestion(
    id: 'empleados',
    prompt: '¿Trabaja alguien con usted?',
    subtitle: '',
    kind: QKind.employeeChips,
    stage: CanvasStage.logo,
    isResolved: _empleadosResolved,
    reset: _empleadosReset,
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

bool _negocioResolved(OnboardingStepperController c, Set<String> _) =>
    c.businessNameValid && c.addressValid;
void _negocioReset(OnboardingStepperController c, Set<String> a) {
  c.setBusinessName('');
  c.setAddress('');
}

bool _tipoResolved(OnboardingStepperController c, Set<String> _) =>
    c.businessTypeSelected;
void _tipoReset(OnboardingStepperController c, Set<String> a) =>
    c.clearBusinessType();

bool _localResolved(OnboardingStepperController c, Set<String> a) =>
    a.contains('local');
void _localReset(OnboardingStepperController c, Set<String> a) =>
    a.remove('local');

bool _logoResolved(OnboardingStepperController c, Set<String> _) =>
    c.logoSelected;
void _logoReset(OnboardingStepperController c, Set<String> a) => c.clearLogo();

bool _empleadosResolved(OnboardingStepperController c, Set<String> a) =>
    a.contains('empleados') || c.hasEmployees != null;
void _empleadosReset(OnboardingStepperController c, Set<String> a) {
  a.remove('empleados');
  c.clearHasEmployees();
}
