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

  // ── Paso 4: Empleados ─────────────────────────────────────────────────────
  bool? hasEmployees; // null = sin respuesta, true = sí, false = no

  // ── Navegación ────────────────────────────────────────────────────────────

  static const int totalSteps = 5; // 0..4

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

  void toggleBusinessType(String type) {
    if (businessTypes.contains(type)) {
      businessTypes.remove(type);
    } else {
      businessTypes.add(type);
    }
    // Auto-activar mesas si tiene bar
    if (businessTypes.contains('bar')) hasTables = true;
    notifyListeners();
  }

  // Legacy single-select (usado por step_business_type viejo)
  void selectBusinessType(String type) {
    businessTypes = [type];
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

      _status = StepperStatus.success;
    } on Exception catch (e) {
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
