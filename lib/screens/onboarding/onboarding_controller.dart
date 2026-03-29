import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';

enum OnboardingStatus { idle, loading, success, error }

class OnboardingController extends ChangeNotifier {
  final ApiService _api;
  final AuthService _auth;

  OnboardingController(this._api, this._auth);

  // Stepper state (0..2)
  int _currentStep = 0;
  int get currentStep => _currentStep;

  // Form data
  String ownerName = '';
  String businessName = '';
  String phone = '';
  String businessType = '';
  String password = '';

  OnboardingStatus _status = OnboardingStatus.idle;
  OnboardingStatus get status => _status;

  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  void nextStep() {
    if (_currentStep < 2) {
      _currentStep++;
      notifyListeners();
    }
  }

  void previousStep() {
    if (_currentStep > 0) {
      _currentStep--;
      notifyListeners();
    }
  }

  void selectBusinessType(String type) {
    businessType = type;
    notifyListeners();
  }

  Future<void> submit() async {
    _status = OnboardingStatus.loading;
    _errorMessage = '';
    notifyListeners();

    try {
      final data = await _api.registerTenantFull({
        'owner_name': ownerName,
        'business_name': businessName,
        'phone': phone,
        'business_type': businessType,
        'password': password,
      });

      // Persistir sesión de forma segura
      // Support both old and new API formats
      if (data.containsKey('access_token')) {
        await _auth.saveSession(
          accessToken: data['access_token'] as String,
          refreshToken: data['refresh_token'] as String? ?? '',
          tenant: (data['tenant'] as Map<String, dynamic>?) ?? {},
        );
      } else {
        await _auth.saveLegacySession(
          token: data['token'] as String,
          tenantId: data['tenant_id'] as int,
          ownerName: data['owner_name'] as String,
          businessName: data['business_name'] as String,
        );
      }

      _status = OnboardingStatus.success;
    } on Exception catch (e) {
      _status = OnboardingStatus.error;
      _errorMessage = _friendlyError(e.toString());
    }

    notifyListeners();
  }

  bool get canSubmit =>
      ownerName.isNotEmpty &&
      businessName.isNotEmpty &&
      phone.length >= 7 &&
      businessType.isNotEmpty &&
      password.length >= 4;

  String _friendlyError(String raw) {
    if (raw.contains('409') || raw.contains('ya está registrado')) {
      return 'Ese número de celular ya tiene una cuenta. ¿Quiere iniciar sesión?';
    }
    if (raw.contains('SocketException') || raw.contains('connection')) {
      return 'Sin conexión. Verifique su internet e intente de nuevo.';
    }
    return 'Algo salió mal. Por favor intente de nuevo.';
  }
}
