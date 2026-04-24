import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Full CRUD for the tenant's digital-payment methods (Nequi,
/// Daviplata, Bancolombia, Breve, Efectivo…). The "express" Nequi
/// shortcut lives in `payment_quick_setup_screen.dart`; this screen
/// is for the multi-wallet scenario and carries the optional QR
/// screenshot upload into R2.
class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key, this.apiOverride});

  /// Injected only by widget tests. Production builds the real
  /// client in the State's initState.
  @visibleForTesting
  final ApiService? apiOverride;

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  /// Injectable API client so tests can substitute a fake without
  /// touching Dio or AuthService. Production still constructs the
  /// real ApiService in initState.
  late final ApiService _api;
  List<Map<String, dynamic>> _methods = [];
  // `_loading` is kept so the pull-to-refresh and Reintentar paths
  // can show a subtle top banner, but we no longer gate the WHOLE
  // screen on it. The P0 regression ("infinite loader") was caused
  // by `_loading = true` plus a silent failure inside fetch: any
  // exception that didn't reach our catch blocks left the screen
  // frozen forever. Now the worst case is the empty-state UI
  // (fully interactive, "Agregar Método" works) plus a retry
  // chip — never a blank spinner.
  bool _loading = true;
  String? _loadError;
  // True the very first time _fetch completes (success or error).
  // Lets us skip the top-of-screen loading banner on subsequent
  // manual refreshes so the "Agregar" flow never gets covered.
  bool _hasCompletedFirstFetch = false;
  String? _uploadingId; // id of the method whose QR is uploading

  // Canonical list of supported wallets. `id` is what ends up in
  // payment_methods.name so it round-trips with the legacy JSON API,
  // and `provider` is the normalised slug consumed by the public
  // catalog for icon/color lookup.
  static const _presets = <_MethodPreset>[
    _MethodPreset(
      id: 'Nequi',
      provider: 'nequi',
      label: 'Nequi',
      helperText: 'Número de celular registrado en Nequi',
      icon: Icons.phone_android_rounded,
      color: Color(0xFF8B5CF6),
      keyboard: TextInputType.phone,
    ),
    _MethodPreset(
      id: 'Daviplata',
      provider: 'daviplata',
      label: 'Daviplata',
      helperText: 'Número de celular de Daviplata',
      icon: Icons.phone_android_rounded,
      color: Color(0xFFEF4444),
      keyboard: TextInputType.phone,
    ),
    _MethodPreset(
      id: 'Bancolombia',
      provider: 'bancolombia',
      label: 'Bancolombia',
      helperText: 'Número de cuenta de ahorros o corriente',
      icon: Icons.account_balance_rounded,
      color: Color(0xFFFDDA24),
      keyboard: TextInputType.number,
    ),
    _MethodPreset(
      id: 'Breve',
      provider: 'breve',
      label: 'Breve (Link / Llave de pago)',
      helperText: 'Pegue aquí su enlace de pago o llave de comercio',
      icon: Icons.link_rounded,
      color: Color(0xFF0EA5E9),
      keyboard: TextInputType.url,
    ),
    _MethodPreset(
      id: 'Efectivo',
      provider: 'efectivo',
      label: 'Efectivo',
      helperText: 'Sin cuenta: el cliente paga en persona',
      icon: Icons.payments_rounded,
      color: Color(0xFF10B981),
      keyboard: TextInputType.text,
    ),
    _MethodPreset(
      id: 'Otro',
      provider: 'otro',
      label: 'Otro',
      helperText: 'Cuenta, llave o dato para que le paguen',
      icon: Icons.account_balance_wallet_rounded,
      color: Color(0xFFEA580C),
      keyboard: TextInputType.text,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    _fetch();
  }

  /// Loads the payment-method list. Three invariants:
  ///
  ///   1. It ALWAYS finishes. Defensive 8 s timeout on top of Dio,
  ///      plus a belt-and-braces `whenComplete` that flips the
  ///      loading flag in the one-in-a-million path where both
  ///      try/catch and timeout somehow miss an error (see the
  ///      `finally` at the bottom).
  ///   2. It ALWAYS clears `_loading`. No return path, including
  ///      widget-was-unmounted-mid-flight, leaves the flag true.
  ///   3. It NEVER hides the form. The caller UI reads `_methods`
  ///      separately from `_loading`, so an empty list keeps the
  ///      "Agregar Método" button and the empty-state copy on
  ///      screen while a second refresh runs in the background.
  Future<void> _fetch() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final list = await _api
          .fetchPaymentMethods()
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() {
        _methods = List<Map<String, dynamic>>.from(list);
        _loadError = null;
      });
    } on AppError catch (e, stack) {
      developer.log('fetchPaymentMethods failed (AppError): ${e.message}',
          name: 'payment_methods_screen', error: e, stackTrace: stack);
      if (!mounted) return;
      setState(() => _loadError = e.message);
    } catch (e, stack) {
      // `on TimeoutException` and any weird TypeError from
      // _extractList land here. We DO NOT rethrow — the whole
      // point of this screen is that it survives backend hiccups.
      developer.log('fetchPaymentMethods failed (unexpected)',
          name: 'payment_methods_screen', error: e, stackTrace: stack);
      if (!mounted) return;
      setState(() => _loadError = 'No se pudieron cargar los métodos de pago.');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _hasCompletedFirstFetch = true;
        });
      }
    }
  }

  Future<void> _toggleActive(String id, bool isActive) async {
    // Optimistic UI: flip the switch immediately, roll back on
    // failure. The tendero's network is often flaky so this keeps
    // the interaction snappy and obvious.
    final originalIndex = _methods.indexWhere((m) => m['id'] == id);
    if (originalIndex == -1) return;
    final original = Map<String, dynamic>.from(_methods[originalIndex]);
    setState(() {
      _methods[originalIndex] = {..._methods[originalIndex], 'is_active': isActive};
    });
    HapticFeedback.selectionClick();
    try {
      await _api.updatePaymentMethod(id, {'is_active': isActive});
    } catch (e) {
      if (!mounted) return;
      // Roll back the optimistic update.
      setState(() => _methods[originalIndex] = original);
      _showError('No se pudo ${isActive ? "activar" : "desactivar"}: $e');
    }
  }

  Future<void> _delete(String id) async {
    // Confirm first — deletions here cascade into the public catalog
    // and the fiado checkout, which are not recoverable from UI.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar método',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        content: const Text(
            'Sus clientes dejarán de ver esta cuenta en el catálogo. '
            '¿Confirmar?',
            style: TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(fontSize: 16)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar',
                style: TextStyle(
                    fontSize: 16,
                    color: AppTheme.error,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.deletePaymentMethod(id);
      await _fetch();
    } catch (e) {
      if (!mounted) return;
      _showError('No se pudo eliminar: $e');
    }
  }

  Future<void> _uploadQR(String methodId) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85, // keep original-ish quality but compress
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (picked == null) return;

    setState(() => _uploadingId = methodId);
    HapticFeedback.selectionClick();
    try {
      final mime = _guessMime(picked.path);
      final updated = await _api.uploadPaymentMethodQR(
        id: methodId,
        filePath: picked.path,
        mimeType: mime,
        filename: picked.name,
      );
      if (!mounted) return;
      // Replace the method in the local list without a full refetch.
      setState(() {
        _methods = _methods
            .map((m) => m['id'] == methodId ? Map<String, dynamic>.from(updated) : m)
            .toList();
        _uploadingId = null;
      });
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('QR subido correctamente',
            style: TextStyle(fontSize: 16)),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
      ));
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() => _uploadingId = null);
      _showError('No se pudo subir el QR: ${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingId = null);
      _showError('No se pudo subir el QR: $e');
    }
  }

  String _guessMime(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/png';
  }

  void _showError(String msg) {
    HapticFeedback.heavyImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 15)),
      backgroundColor: AppTheme.error,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showAddSheet() {
    _MethodPreset selected = _presets.first;
    final detailsCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: StatefulBuilder(
            builder: (ctx, setSheetState) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD6D0C8),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Text('Nuevo Método de Pago',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87)),
                const SizedBox(height: 4),
                const Text(
                    'Así sus clientes saben dónde pagarle.',
                    style: TextStyle(
                        fontSize: 14, color: AppTheme.textSecondary)),
                const SizedBox(height: 20),

                // Large "where" selector
                DropdownButtonFormField<_MethodPreset>(
                  initialValue: selected,
                  isExpanded: true,
                  style: const TextStyle(
                      fontSize: 18,
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    labelText: '¿Por dónde le pagan?',
                    labelStyle: TextStyle(fontSize: 15),
                    prefixIcon:
                        Icon(Icons.account_balance_wallet_rounded),
                  ),
                  items: _presets
                      .map((p) => DropdownMenuItem<_MethodPreset>(
                            value: p,
                            child: Row(
                              children: [
                                Icon(p.icon, color: p.color, size: 22),
                                const SizedBox(width: 10),
                                Flexible(
                                    child: Text(p.label,
                                        overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setSheetState(() => selected = v);
                  },
                ),
                const SizedBox(height: 18),

                // Contextual input — the label & helper text shift
                // with the picked preset so "Breve" is understood
                // ("Pegue aquí su enlace de pago o llave de
                // comercio") without extra tap-to-see-tooltip.
                TextField(
                  controller: detailsCtrl,
                  style: const TextStyle(
                      fontSize: 18,
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600),
                  keyboardType: selected.keyboard,
                  decoration: InputDecoration(
                    labelText: selected.id == 'Breve'
                        ? 'Enlace o llave de pago'
                        : selected.id == 'Efectivo'
                            ? 'Nota para el cliente (opcional)'
                            : 'Número de celular o cuenta',
                    helperText: selected.helperText,
                    helperMaxLines: 2,
                    prefixIcon: Icon(selected.icon, color: selected.color),
                  ),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  height: 60,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      // Efectivo / Otro may be blank; the rest need
                      // at least some account hint so the buyer
                      // doesn't type into the void.
                      final details = detailsCtrl.text.trim();
                      final needsDetails = !(selected.id == 'Efectivo' ||
                          selected.id == 'Otro');
                      if (needsDetails && details.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                          content: Text(
                              'Ingrese ${selected.id == 'Breve' ? 'el enlace' : 'el número'}',
                              style: const TextStyle(fontSize: 15)),
                          backgroundColor: AppTheme.warning,
                          behavior: SnackBarBehavior.floating,
                        ));
                        return;
                      }
                      Navigator.of(ctx).pop();
                      try {
                        await _api.createPaymentMethod({
                          'name': selected.id,
                          'provider': selected.provider,
                          'account_details': details,
                        });
                        await _fetch();
                      } on AppError catch (e) {
                        if (!mounted) return;
                        _showError('No se pudo guardar: ${e.message}');
                      } catch (e) {
                        if (!mounted) return;
                        _showError('No se pudo guardar: $e');
                      }
                    },
                    icon: const Icon(Icons.check_rounded, size: 24),
                    label: const Text('Agregar',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  _MethodPreset _presetFor(Map<String, dynamic> m) {
    final provider =
        (m['provider'] as String? ?? '').trim().toLowerCase();
    final name = (m['name'] as String? ?? '').trim().toLowerCase();
    for (final p in _presets) {
      if (p.provider == provider) return p;
    }
    for (final p in _presets) {
      if (p.id.toLowerCase() == name) return p;
    }
    return _presets.last; // fallback to "Otro"
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFBF7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Métodos de Pago',
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary)),
      ),
      body: _buildBody(),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBF7),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SizedBox(
          height: 60,
          child: ElevatedButton.icon(
            key: const Key('pm_add_method_button'),
            onPressed: _showAddSheet,
            icon: const Icon(Icons.add_rounded, size: 24),
            label: const Text('Agregar Método',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
            ),
          ),
        ),
      ),
    );
  }

  /// Invariant: this method NEVER returns a full-screen spinner.
  ///
  /// State → render mapping:
  ///   * first fetch still in-flight  → empty state + top loading
  ///     banner (the user can already tap "Agregar Método" below
  ///     and start creating a record if they know what they want)
  ///   * error + empty list           → empty state + red retry
  ///     banner with "Reintentar"
  ///   * error + non-empty list       → list + red retry banner
  ///   * success + empty list         → empty state, no banners
  ///   * success + non-empty list     → list, no banners
  ///
  /// The previous implementation gated EVERYTHING on `_loading`
  /// and turned into the infinite-spinner regression whenever the
  /// async chain hung (captive wifi, cold start, silent TypeError
  /// inside _extractList, JWT refresh stuck). Now the worst case
  /// is a visible banner — never a dead screen.
  Widget _buildBody() {
    final hasMethods = _methods.isNotEmpty;
    final showFirstLoadBanner = _loading && !_hasCompletedFirstFetch;
    final showErrorBanner = _loadError != null;

    final content = hasMethods
        ? ListView.separated(
            padding: const EdgeInsets.all(20),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: _methods.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final m = _methods[i];
              final id = (m['id'] as String?) ?? '';
              return _MethodCard(
                method: m,
                preset: _presetFor(m),
                isUploading: _uploadingId == id,
                onUploadQR: () => _uploadQR(id),
                onToggleActive: (v) => _toggleActive(id, v),
                onDelete: () {
                  HapticFeedback.mediumImpact();
                  _delete(id);
                },
              );
            },
          )
        : _EmptyState(onAdd: _showAddSheet);

    return RefreshIndicator(
      onRefresh: _fetch,
      color: AppTheme.primary,
      child: Column(
        children: [
          if (showFirstLoadBanner)
            const _LoadingBanner()
          else if (showErrorBanner)
            _ErrorBanner(message: _loadError!, onRetry: _fetch),
          Expanded(child: content),
        ],
      ),
    );
  }
}

// ─── Sub-widgets ────────────────────────────────────────────────────────────

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.method,
    required this.preset,
    required this.isUploading,
    required this.onUploadQR,
    required this.onToggleActive,
    required this.onDelete,
  });

  final Map<String, dynamic> method;
  final _MethodPreset preset;
  final bool isUploading;
  final VoidCallback onUploadQR;
  final ValueChanged<bool> onToggleActive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final name = (method['name'] as String? ?? '').trim();
    final details = (method['account_details'] as String? ?? '').trim();
    final qr = (method['qr_image_url'] as String? ?? '').trim();
    // `is_active` may be missing on old payloads; default to true so
    // legacy methods stay visible in the catalog instead of silently
    // disappearing.
    final isActive = (method['is_active'] as bool?) ?? true;
    final isLink = preset.provider == 'breve' ||
        (details.startsWith('http://') || details.startsWith('https://'));
    final color = preset.color;

    return Opacity(
      // Faded card when deactivated → instantly readable "this is
      // off" cue for older tenderos without decoding switch state.
      opacity: isActive ? 1.0 : 0.6,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(preset.icon, color: color, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87)),
                      if (details.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              if (isLink)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(right: 6),
                                  child: Icon(Icons.link_rounded,
                                      size: 16, color: color),
                                ),
                              Expanded(
                                child: Text(
                                  details,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      color: AppTheme.textSecondary,
                                      fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                // Big visible active toggle (≥ 48 px tap target).
                Switch(
                  value: isActive,
                  onChanged: onToggleActive,
                  activeThumbColor: AppTheme.success,
                ),
              ],
            ),

            // QR row — thumbnail if present, upload button otherwise.
            // For Breve / link payments the QR is rarely needed but
            // still offered in case the tendero has a generated one.
            const SizedBox(height: 10),
            _QRRow(
              qrUrl: qr,
              color: color,
              isUploading: isUploading,
              onUpload: onUploadQR,
            ),

            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Eliminar',
                    style: TextStyle(fontSize: 14)),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.error,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QRRow extends StatelessWidget {
  const _QRRow({
    required this.qrUrl,
    required this.color,
    required this.isUploading,
    required this.onUpload,
  });

  final String qrUrl;
  final Color color;
  final bool isUploading;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    if (isUploading) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        alignment: Alignment.center,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  color: AppTheme.primary, strokeWidth: 2.5),
            ),
            SizedBox(width: 12),
            Text('Subiendo QR…',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary)),
          ],
        ),
      );
    }

    if (qrUrl.isNotEmpty) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              qrUrl,
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 72,
                height: 72,
                color: const Color(0xFFF5F1EA),
                child: const Icon(Icons.qr_code_2_rounded,
                    color: AppTheme.textSecondary, size: 30),
              ),
              loadingBuilder: (ctx, child, progress) {
                if (progress == null) return child;
                return Container(
                  width: 72,
                  height: 72,
                  color: const Color(0xFFF5F1EA),
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 18,
                    height: 18,
                    child:
                        CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Código QR configurado',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.success)),
                const SizedBox(height: 4),
                const Text(
                    'Sus clientes lo ven en el catálogo al pagar.',
                    style: TextStyle(
                        fontSize: 13, color: AppTheme.textSecondary)),
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: onUpload,
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('Cambiar QR',
                      style: TextStyle(fontSize: 14)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // No QR yet — prominent dotted CTA.
    return InkWell(
      onTap: onUpload,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: color.withValues(alpha: 0.5),
            width: 1.5,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.qr_code_2_rounded, color: color, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('📸 Subir foto de su código QR',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: color)),
                  const SizedBox(height: 2),
                  const Text('Opcional — así sus clientes escanean',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: color.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('pm_empty_state'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance_wallet_rounded,
                size: 72,
                color: AppTheme.textSecondary.withValues(alpha: 0.35)),
            const SizedBox(height: 20),
            const Text('Sin métodos de pago',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 8),
            const Text(
              'Agregue Nequi, Daviplata o su cuenta para que los clientes '
              'puedan pagar sin tener que preguntarle.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16,
                  height: 1.4,
                  color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Agregar el primero',
                  style: TextStyle(fontSize: 16)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.primary, width: 1.5),
                padding: const EdgeInsets.symmetric(
                    horizontal: 22, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thin banner shown across the top during the FIRST fetch so the
/// user sees something is happening but can still interact with
/// the empty state below (the primary "Agregar Método" button
/// lives in the bottom nav and is always tappable).
class _LoadingBanner extends StatelessWidget {
  const _LoadingBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('pm_loading_banner'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: const Color(0xFFFFF7EC),
      child: const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                color: AppTheme.primary, strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Cargando sus métodos de pago...',
              style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Retryable error banner. Replaces the old full-screen _ErrorState
/// so the empty-state / list below it stays interactive — the user
/// can still add a new method even while the server is flaky.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('pm_error_banner'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
      color: const Color(0xFFFEE2E2),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded,
              color: AppTheme.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.error,
                  fontWeight: FontWeight.w600),
            ),
          ),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Reintentar',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.error,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodPreset {
  final String id; // matches payment_methods.name (legacy)
  final String provider; // normalised slug stored in payment_methods.provider
  final String label;
  final String helperText;
  final IconData icon;
  final Color color;
  final TextInputType keyboard;
  const _MethodPreset({
    required this.id,
    required this.provider,
    required this.label,
    required this.helperText,
    required this.icon,
    required this.color,
    required this.keyboard,
  });
}
