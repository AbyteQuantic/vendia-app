import 'package:flutter/material.dart';

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
  // Optional logo-apply hooks. Called AFTER registerTenantFull lands
  // so they have a real JWT in scope. Failures are swallowed — the
  // account is already created at that point and the merchant can
  // re-apply the logo from Configuración.
  final Future<void> Function(String description)? generateLogoIA;
  final Future<void> Function(String localPath)? uploadLogoFile;

  OnboardingStepperController({
    required this.apiCall,
    required this.saveSession,
    this.generateLogoIA,
    this.uploadLogoFile,
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

  // ── Paso 5: Logo (intent capture, applied post-register) ────────────────
  // The logo step now sits BEFORE registration in the visual flow so the
  // merchant feels like they're crafting the brand before the account
  // is real. Both the IA endpoint and the upload endpoint require a
  // tenant_id, so the actual API calls are deferred to submit() — we
  // capture intent here and replay it after registerTenantFull() lands.
  //
  //   - logoIntent == 'ai'      → call generateLogoAI(details=logoDescription)
  //   - logoIntent == 'gallery' → call uploadLogo(File(logoLocalPath))
  //   - logoIntent == ''        → skip; logo remains null
  String logoIntent = '';
  String logoDescription = '';
  String logoLocalPath = '';

  void setLogoIA(String description) {
    logoIntent = 'ai';
    logoDescription = description.trim();
    logoLocalPath = '';
    notifyListeners();
  }

  void setLogoFile(String path) {
    logoIntent = 'gallery';
    logoLocalPath = path;
    logoDescription = '';
    notifyListeners();
  }

  void clearLogoIntent() {
    logoIntent = '';
    logoDescription = '';
    logoLocalPath = '';
    notifyListeners();
  }

  // ── Paso 6: Empleados ─────────────────────────────────────────────────────
  bool? hasEmployees; // null = sin respuesta, true = sí, false = no

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
    businessTypes = [type];
    // enable_tables in the backend fires when the type is in the food
    // stack — mirror it here so the branches/config step defaults are
    // sensible even before the backend recomputes feature_flags.
    hasTables = {'bar', 'restaurante', 'comidas_rapidas'}.contains(type);
    notifyListeners();
  }

  void setMultipleBranches(bool value) {
    hasMultipleBranches = value;
    notifyListeners();
  }

  void setHasEmployees(bool value) {
    hasEmployees = value;
    // Bar con mesas: sugerencia automática de has_tables
    if (businessType == 'bar') hasTables = true;
    notifyListeners();
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> submit() async {
    _status = StepperStatus.loading;
    _errorMessage = '';
    notifyListeners();

    try {
      final payload = _buildPayload();
      final data = await apiCall(payload);

      await saveSession(data);

      // Replay the logo intent that was captured in step 5. From the
      // merchant's POV the logo is applied AS PART OF "Crear cuenta" —
      // they don't see the two-phase orchestration. Failures are
      // non-fatal: account is real, logo stays unset, merchant can
      // try again from Configuración.
      if (logoIntent == 'ai' &&
          logoDescription.isNotEmpty &&
          generateLogoIA != null) {
        try {
          await generateLogoIA!(logoDescription);
        } catch (_) {
          // Swallow — see comment above.
        }
      } else if (logoIntent == 'gallery' &&
          logoLocalPath.isNotEmpty &&
          uploadLogoFile != null) {
        try {
          await uploadLogoFile!(logoLocalPath);
        } catch (_) {
          // Swallow.
        }
      }

      _status = StepperStatus.success;
    } catch (e) {
      _status = StepperStatus.error;
      _errorMessage = _friendlyError(e.toString());
    }

    notifyListeners();
  }

  Map<String, dynamic> _buildPayload() {
    return {
      'owner': {
        'name': '$ownerName $ownerLastName'.trim(),
        'phone': phone,
        'password': pin,
      },
      'business': {
        'name': businessName,
        'razon_social': razonSocial,
        'nit': nit,
        'address': address,
        'type': businessType, // tipo principal
        'types': businessTypes, // todos los portafolios
        'has_multiple_branches': hasMultipleBranches,
      },
      'config': {
        'sale_types': saleTypes,
        'has_showcases': hasShowcases,
        'has_tables': hasTables,
      },
      // Fase 2: empleados se agrega en el módulo Administrar (Fase 4)
      'employees': [],
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
