// Spec: specs/023-capacidades-opcionales-negocio/spec.md
import 'package:flutter/material.dart';
import '../../utils/business_capability_map.dart';

enum StepperStatus { idle, loading, success, error }

/// Controlador del Stepper de onboarding (4 pasos).
///
/// Usa dependency injection por funciones para facilitar el testing:
///   - [apiCall]     → llama a POST /api/v1/tenant/register
///   - [saveSession] → persiste el JWT en secure storage
///
/// En producción, inyectar las funciones reales de ApiService y AuthService.
/// En tests, inyectar funciones fake sin dependencias externas.
class OnboardingStepperController extends ChangeNotifier {
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) apiCall;
  final Future<void> Function(Map<String, dynamic> responseData) saveSession;

  OnboardingStepperController({
    required this.apiCall,
    required this.saveSession,
  });

  // ── Estado del stepper ────────────────────────────────────────────────────
  int _currentStep = 0;
  int get currentStep => _currentStep;

  StepperStatus _status = StepperStatus.idle;
  StepperStatus get status => _status;

  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  // ── Paso 1: Propietario ───────────────────────────────────────────────────
  String ownerName = '';
  String ownerLastName = '';
  String phone = '';
  String pin = '';

  // Spec 045 — confirmación de PIN. NO se persiste ni viaja en el payload:
  // es solo un gate de validación (pin == confirmPin). Vive aquí para que el
  // getter canRegister sea la única fuente de verdad del onboarding agéntico.
  String confirmPin = '';

  // ── Paso 2: Tienda ────────────────────────────────────────────────────────
  String businessName = '';
  String razonSocial = '';
  String nit = '';
  String address = '';

  // ── Paso 2.5: Multi-sede ──────────────────────────────────────────────────
  bool hasMultipleBranches = false;

  // ── Paso 3: Configuración (Portafolios — selección múltiple) ────────────
  List<String> businessTypes = [];
  List<String> saleTypes = ['products'];
  bool hasShowcases = false;
  bool hasTables = false;

  // ── Capacidades opcionales (F023) ─────────────────────────────────────────
  // Estos toggles se incluyen en config.{offers_services, sells_by_weight}
  // dentro de _buildPayload. Cada uno se muestra solo si el tipo elegido no
  // concede ya esa capacidad — ver business_capability_map.dart.
  bool offersServices = false;
  bool sellsByWeight = false;

  void setOffersServices(bool value) {
    offersServices = value;
    notifyListeners();
  }

  void setSellsByWeight(bool value) {
    sellsByWeight = value;
    notifyListeners();
  }

  void setHasTables(bool value) {
    hasTables = value;
    notifyListeners();
  }

  // Backward compat getter (tipo principal = primero de la lista)
  String get businessType =>
      businessTypes.isNotEmpty ? businessTypes.first : '';

  /// Human-readable labels for selected business types (for AI prompts & UI).
  /// Keys MUST match the backend whitelist (models.ValidBusinessTypes).
  static const _typeLabels = {
    'tienda_barrio': 'Tienda de Barrio',
    'minimercado': 'Minimercado',
    'deposito_construccion': 'Depósito de Construcción',
    'restaurante': 'Restaurante',
    'comidas_rapidas': 'Comidas Rápidas',
    'bar': 'Bar/Licorera',
    'manufactura': 'Fábrica/Manufactura',
    'reparacion_muebles': 'Reparación/Mueblería',
    'emprendimiento_general': 'Emprendimiento General',
    'academias_instituciones': 'Academias e Instituciones',
  };

  /// Returns readable labels for all selected business types.
  List<String> get businessTypeLabels =>
      businessTypes.map((t) => _typeLabels[t] ?? t).toList();

  /// Single string for AI prompts: "Tienda/Minimercado y Bar/Licorera"
  String get businessTypesSummary {
    final labels = businessTypeLabels;
    if (labels.isEmpty) return '';
    if (labels.length == 1) return labels.first;
    return '${labels.sublist(0, labels.length - 1).join(", ")} y ${labels.last}';
  }

  // ── Paso 5: Logo (resolved BEFORE register via public preview API) ───
  // Step 5 now actually generates / uploads the logo via two public
  // routes (POST /api/v1/auth/preview-logo, .../preview-logo-upload).
  // The resulting URL is stored here and folded into the register
  // payload at business.logo_url so the tenant is born with its
  // brand mark already attached.
  //
  // logoDescription persists across step revisits so a Back-then-
  // Next doesn't wipe the merchant's typed intent.
  String logoUrl = '';
  String logoDescription = '';

  void setLogoUrl(String url) {
    logoUrl = url;
    notifyListeners();
  }

  void clearLogo() {
    logoUrl = '';
    notifyListeners();
  }

  // ── Paso 6: Empleados ─────────────────────────────────────────────────────
  bool? hasEmployees; // null = sin respuesta, true = sí, false = no

  // ── Términos y Servicios (Spec 098, Fase 1) ───────────────────────────────
  // Aceptación OBLIGATORIA de los T&C (incluye la cláusula de uso colaborativo
  // de imágenes). Se envía como `accept_terms` en el payload de registro; el
  // backend rechaza con 400 si es false. El botón "Crear mi cuenta" del
  // onboarding se deshabilita hasta que esto sea true.
  bool acceptedTerms = false;

  void setAcceptedTerms(bool value) {
    acceptedTerms = value;
    notifyListeners();
  }

  // ── Navegación ────────────────────────────────────────────────────────────

  // Six visible steps. The LAST step (logo, index 5) is deliberately
  // post-registration: submit() runs at the end of step 4 (employees)
  // and only on success do we advance to the logo screen, where the
  // authenticated session lets us call /tenant/generate-logo with a
  // real tenant_id. Pre-registration logo generation never worked
  // ("Los logos se generarán después del registro" was the dead-end
  // message that triggered this redesign).
  static const int totalSteps = 6;

  void nextStep() {
    if (_currentStep < totalSteps - 1) {
      _currentStep++;
      notifyListeners();
    }
  }

  void previousStep() {
    if (_currentStep > 0) {
      _currentStep--;
      _errorMessage = '';
      notifyListeners();
    }
  }

  /// Sets the tenant's primary business type. The backend schema still
  /// takes an array (`business_types`) because migration 020 modelled
  /// it that way, but the onboarding UX now enforces single selection
  /// to avoid ambiguous feature-flag combos (e.g. a tenant flagged as
  /// both "bar" and "manufactura" would receive enable_tables=true
  /// AND enable_services=true and the POS would render conflicting
  /// CTAs). We write a 1-element array so the wire format stays
  /// stable.
  void setPrimaryBusinessType(String type) {
    _setPrimaryBusinessTypeCore(type);
    notifyListeners();
  }

  /// Núcleo sin notify (Spec 045): aplica el tipo + sus side-effects de
  /// feature-flags (hasTables food, limpia capacidades implícitas) sin
  /// disparar notifyListeners — para que applyParseResult notifique una sola
  /// vez (INV-4). setPrimaryBusinessType lo envuelve y notifica.
  void _setPrimaryBusinessTypeCore(String type) {
    businessTypes = [type];
    // enable_tables in the backend fires when the type is in the food
    // stack — mirror it here so the branches/config step defaults are
    // sensible even before the backend recomputes feature_flags.
    hasTables = {'bar', 'restaurante', 'comidas_rapidas'}.contains(type);

    // F023: limpiar los toggles opcionales que el nuevo tipo ya implica,
    // de modo que no queden activados valores que el tipo hace redundantes.
    final implied = impliedCapabilities(type);
    if (implied.contains(OptionalCapability.services)) offersServices = false;
    if (implied.contains(OptionalCapability.fractionalUnits)) sellsByWeight = false;
    // hasTables se maneja arriba (el tipo food ya lo activa implícitamente)
  }

  void setMultipleBranches(bool value) {
    hasMultipleBranches = value;
    notifyListeners();
  }

  void setHasEmployees(bool value) {
    _setHasEmployeesCore(value);
    notifyListeners();
  }

  /// Spec 045-anim — undo: limpia el tipo de negocio (vuelve a "no resuelto").
  /// Al re-elegir, setPrimaryBusinessType recalcula los feature-flags.
  void clearBusinessType() {
    businessTypes = [];
    notifyListeners();
  }

  /// Spec 045-anim — undo: vuelve la respuesta de empleados a "sin responder".
  void clearHasEmployees() {
    hasEmployees = null;
    notifyListeners();
  }

  /// Spec 045 — "Empezar de nuevo": limpia TODO el estado del onboarding para
  /// que el usuario pueda descartar datos restaurados de una sesión anterior.
  /// La vista agéntica también borra la persistencia (SharedPreferences) y su
  /// propio estado de navegación (_answered/_trail/_qIndex). Notifica una sola
  /// vez al final (INV-4). El PIN/confirmPin también se limpian: nunca se
  /// persisten, pero un reset debe dejar el formulario en blanco real.
  void reset() {
    _currentStep = 0;
    _status = StepperStatus.idle;
    _errorMessage = '';
    ownerName = '';
    ownerLastName = '';
    phone = '';
    pin = '';
    confirmPin = '';
    businessName = '';
    razonSocial = '';
    nit = '';
    address = '';
    hasMultipleBranches = false;
    businessTypes = [];
    saleTypes = ['products'];
    hasShowcases = false;
    hasTables = false;
    offersServices = false;
    sellsByWeight = false;
    logoUrl = '';
    logoDescription = '';
    hasEmployees = null;
    acceptedTerms = false;
    notifyListeners();
  }

  /// Núcleo sin notify (Spec 045) — ver _setPrimaryBusinessTypeCore.
  void _setHasEmployeesCore(bool value) {
    hasEmployees = value;
    // Bar con mesas: sugerencia automática de has_tables
    if (businessType == 'bar') hasTables = true;
  }

  // ── Setters de texto (Spec 045) ───────────────────────────────────────────
  // El onboarding agéntico edita los campos en mini-formularios y necesita que
  // canRegister + los resúmenes de las Smart Cards se refresquen en vivo. Los
  // Form del wizard clásico siguen escribiendo el campo directo (sin notify),
  // así que estos setters no rompen nada — solo añaden el notify que la UI
  // reactiva necesita.
  void setOwnerName(String v) {
    ownerName = v;
    notifyListeners();
  }

  void setOwnerLastName(String v) {
    ownerLastName = v;
    notifyListeners();
  }

  /// Spec 106 (feedback del fundador 2026-07-19): UNA sola caja para el
  /// nombre completo — el sistema separa nombre y apellidos solo. Regla
  /// determinista: primer token = nombre (para saludos: "¡Todo listo,
  /// Carmen!"), el resto = apellidos. El backend recibe el nombre COMPLETO
  /// re-unido (`_buildPayload` une nombre + apellidos), así que la partición
  /// exacta nombre/segundo-nombre/apellido no altera lo persistido. Si el
  /// tendero dicta por voz/IA, el parse de Gemini sigue haciendo la
  /// separación semántica fina.
  void setOwnerFullName(String v) {
    final parts =
        v.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) {
      ownerName = '';
      ownerLastName = '';
    } else if (parts.length == 1) {
      ownerName = parts.first;
      ownerLastName = '';
    } else {
      ownerName = parts.first;
      ownerLastName = parts.sublist(1).join(' ');
    }
    notifyListeners();
  }

  void setPhone(String v) {
    phone = v;
    notifyListeners();
  }

  void setPin(String v) {
    pin = v;
    notifyListeners();
  }

  void setConfirmPin(String v) {
    confirmPin = v;
    notifyListeners();
  }

  void setBusinessName(String v) {
    businessName = v;
    notifyListeners();
  }

  void setRazonSocial(String v) {
    razonSocial = v;
    notifyListeners();
  }

  void setNit(String v) {
    nit = v;
    notifyListeners();
  }

  void setAddress(String v) {
    address = v;
    notifyListeners();
  }

  // ── Validación re-alojada + gate de registro (Spec 045) ───────────────────
  // Estos predicados eran reglas dispersas en los Form de step_owner/
  // step_business y en los gates de _onNext. El onboarding agéntico no usa
  // esos widgets, así que la validación vive aquí como única fuente de verdad.

  /// Tipos de negocio válidos (whitelist espejo de models.ValidBusinessTypes).
  static const Set<String> validBusinessTypes = {
    'tienda_barrio',
    'minimercado',
    'deposito_construccion',
    'restaurante',
    'comidas_rapidas',
    'bar',
    'manufactura',
    'reparacion_muebles',
    'emprendimiento_general',
    'academias_instituciones',
  };

  bool get ownerValid =>
      ownerName.trim().isNotEmpty && ownerLastName.trim().isNotEmpty;

  /// Teléfono: al menos 7 dígitos (regla original de step_owner).
  bool get phoneValid =>
      phone.replaceAll(RegExp(r'\D'), '').length >= 7;

  /// PIN: 4-8 dígitos numéricos (regla original de step_owner).
  bool get pinValid {
    final p = pin.trim();
    return p.length >= 4 && p.length <= 8 && RegExp(r'^\d+$').hasMatch(p);
  }

  bool get pinConfirmed => pin.isNotEmpty && pin == confirmPin;

  bool get businessNameValid => businessName.trim().isNotEmpty;

  /// Dirección requerida (Spec 045 — aprobado por el fundador 2026-06-13).
  bool get addressValid => address.trim().isNotEmpty;

  bool get businessTypeSelected => businessTypes.isNotEmpty;

  bool get logoSelected => logoUrl.trim().isNotEmpty;

  /// Gate único del botón "Crear mi cuenta". Spec 106 — registro corto:
  /// SOLO credenciales; el nombre del negocio, los tipos y el logo los
  /// configura la conversación con Vendi después de crear la cuenta.
  bool get canRegister =>
      ownerValid && phoneValid && pinValid && pinConfirmed;

  // ── Integración IA (Spec 045) ─────────────────────────────────────────────

  /// Sugerencia de origen del logo devuelta por la IA ('generar'|'subir'|
  /// 'omitir'). SOLO enruta la Smart Card de logo (D11); NUNCA escribe
  /// logoUrl directo — eso lo resuelven los endpoints preview-logo*.
  String? suggestedLogoIntent;

  /// Aplica el resultado del parseo IA (POST /auth/onboarding-parse) al estado.
  ///
  /// Reglas (Spec 045):
  ///  - merge PARCIAL: solo escribe campos no-null y FUERA de needs_confirmation;
  ///    los ausentes/null no pisan lo ya escrito a mano (D7).
  ///  - escribe SIEMPRE por setter/núcleo (conserva side-effects de
  ///    business_type y has_employees) (D2).
  ///  - IGNORA el PIN aunque venga (dato sensible, D10).
  ///  - business_type fuera de la whitelist → se descarta (defensa, D9).
  ///  - logo_intent NO escribe logoUrl, solo expone suggestedLogoIntent (D11).
  ///  - notifyListeners() UNA sola vez al final (INV-4).
  void applyParseResult(Map<String, dynamic> result) {
    final fields = (result['fields'] as Map?)?.cast<String, dynamic>() ?? {};
    final needs = ((result['needs_confirmation'] as List?) ?? const [])
        .map((e) => e.toString())
        .toSet();

    bool present(String k) =>
        fields.containsKey(k) && fields[k] != null && !needs.contains(k);

    String? text(String k) => present(k) ? fields[k].toString().trim() : null;
    bool? flag(String k) => present(k) ? fields[k] == true : null;

    final on = text('owner_name');
    if (on != null && on.isNotEmpty) ownerName = on;
    final ol = text('owner_last_name');
    if (ol != null && ol.isNotEmpty) ownerLastName = ol;

    final ph = text('phone');
    if (ph != null) {
      final digits = ph.replaceAll(RegExp(r'\D'), '');
      if (digits.isNotEmpty) phone = digits;
    }

    final bn = text('business_name');
    if (bn != null && bn.isNotEmpty) businessName = bn;
    final rs = text('razon_social');
    if (rs != null && rs.isNotEmpty) razonSocial = rs;
    final nt = text('nit');
    if (nt != null && nt.isNotEmpty) nit = nt;
    final ad = text('address');
    if (ad != null && ad.isNotEmpty) address = ad;

    final bt = text('business_type');
    if (bt != null && validBusinessTypes.contains(bt)) {
      _setPrimaryBusinessTypeCore(bt);
    }

    final mb = flag('has_multiple_branches');
    if (mb != null) hasMultipleBranches = mb;
    final os = flag('offers_services');
    if (os != null) offersServices = os;
    final sw = flag('sells_by_weight');
    if (sw != null) sellsByWeight = sw;
    final ht = flag('has_tables');
    if (ht != null) hasTables = ht;
    final he = flag('has_employees');
    if (he != null) _setHasEmployeesCore(he);

    final li = text('logo_intent');
    if (li != null && const {'generar', 'subir', 'omitir'}.contains(li)) {
      suggestedLogoIntent = li;
    }
    // PIN y captcha: intencionalmente ignorados (D10).

    notifyListeners();
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> submit() async => submitWithCaptcha(null);

  /// Envía el formulario incluyendo el [captchaToken] si está disponible (F024).
  Future<void> submitWithCaptcha(String? captchaToken) async {
    _status = StepperStatus.loading;
    _errorMessage = '';
    notifyListeners();

    try {
      final payload = _buildPayload();
      // F024: incluir el token de captcha en el payload para que
      // OnboardingStepperScreen lo extraiga y lo pase a registerTenantFull.
      if (captchaToken != null && captchaToken.isNotEmpty) {
        payload['captcha_token'] = captchaToken;
      }
      final data = await apiCall(payload);

      await saveSession(data);

      _status = StepperStatus.success;
    } catch (e) {
      _status = StepperStatus.error;
      _errorMessage = _friendlyError(e.toString());
    }

    notifyListeners();
  }

  /// Muestra un mensaje de error de captcha sin cambiar el estado de loading.
  /// Usado cuando el widget de captcha reporta un error antes del submit.
  void setCaptchaError(String message) {
    _status = StepperStatus.error;
    _errorMessage = message;
    notifyListeners();
  }

  Map<String, dynamic> _buildPayload() {
    // Spec 106 — registro MÍNIMO: solo credenciales. El backend pone el
    // placeholder "Mi negocio" y Vendi configura todo lo demás conversando.
    // Si una sesión restaurada de la app vieja trae datos del negocio, se
    // envían (no se pierden), pero ya no son requisito.
    return {
      'owner': {
        'name': '$ownerName $ownerLastName'.trim(),
        'phone': phone,
        'password': pin,
      },
      if (businessName.trim().isNotEmpty || businessTypes.isNotEmpty)
        'business': {
          if (businessName.trim().isNotEmpty) 'name': businessName,
          if (address.trim().isNotEmpty) 'address': address,
          if (businessType.isNotEmpty) 'type': businessType,
          if (businessTypes.isNotEmpty) 'types': businessTypes,
          if (logoUrl.isNotEmpty) 'logo_url': logoUrl,
        },
      'employees': [],
      // Spec 098 (Fase 1): aceptación de T&C. OnboardingStepperScreen lo
      // extrae del payload y lo pasa como acceptTerms a la llamada real.
      'accept_terms': acceptedTerms,
      // Spec 106 (FR-13): el registro mostró el aviso de que la conversación
      // con Vendi se guarda para mejorar el asistente.
      'data_notice_accepted': true,
    };
  }

  String _friendlyError(String raw) {
    if (raw.contains('409') || raw.contains('ya está registrado')) {
      return 'Ese número de celular ya tiene una cuenta.\n¿Desea iniciar sesión?';
    }
    if (raw.contains('SocketException') || raw.contains('connection')) {
      return 'Sin conexión. Verifique su internet e intente de nuevo.';
    }
    return 'Algo salió mal. Por favor intente de nuevo.';
  }
}
