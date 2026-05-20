// Spec: specs/024-captcha-registro-login/spec.md
import 'package:cloudflare_turnstile/cloudflare_turnstile.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Widget reutilizable que envuelve el CAPTCHA de Cloudflare Turnstile.
///
/// **Kill-switch (FR-10):** si el site key está vacío (ningún dart-define y
/// build release), el widget devuelve [SizedBox.shrink] y las pantallas
/// funcionan exactamente igual que antes de F024.
///
/// **Activación:** construir con
/// `--dart-define=TURNSTILE_SITE_KEY=<clave real>`.
///
/// Uso básico:
/// ```dart
/// TurnstileCaptcha(
///   onToken: (token) => setState(() => _captchaToken = token),
///   onError: (msg) => ScaffoldMessenger.of(context).showSnackBar(…),
/// )
/// ```
///
/// Para resetear (AC-06), mantén una clave global o usa el método estático:
/// ```dart
/// final _captchaKey = GlobalKey<TurnstileCaptchaState>();
/// // …
/// _captchaKey.currentState?.reset();
/// ```
class TurnstileCaptcha extends StatefulWidget {
  const TurnstileCaptcha({
    super.key,
    required this.onToken,
    required this.onError,
    /// Sobrescritura de site key (tests y pantallas que forwarden su propio override).
    this.siteKeyOverride,
    /// Builder sustituto del widget interno Turnstile (usado en tests y pantallas con override).
    this.turnstileWidgetBuilder,
  });

  /// Callback invocado al recibir un token válido de Turnstile.
  final void Function(String token) onToken;

  /// Callback invocado si el widget reporta un error.
  /// El mensaje viene en español para mostrarlo directo al usuario.
  final void Function(String message) onError;

  /// Sobrescritura de site key.
  /// Usar solo desde tests o desde pantallas que tengan su propio override de test.
  final String? siteKeyOverride;

  /// Builder sustituto que reemplaza al [CloudflareTurnstile] real.
  /// Usado en tests y en pantallas que forwardeen su propio override.
  final Widget Function(TurnstileCaptchaState state)? turnstileWidgetBuilder;

  /// Site key efectiva: primero el override, luego dart-define, o vacío (kill-switch).
  ///
  /// Kill-switch (FR-10): sin dart-define TURNSTILE_SITE_KEY en build,
  /// el widget queda invisible tanto en debug como en release.
  /// Para desarrollo local con captcha activo, pasar
  /// `--dart-define=TURNSTILE_SITE_KEY=1x00000000000000000000AA`.
  String get effectiveSiteKey {
    if (siteKeyOverride != null) return siteKeyOverride!;
    const envKey = String.fromEnvironment('TURNSTILE_SITE_KEY');
    return envKey; // vacío → kill-switch activo
  }

  @override
  State<TurnstileCaptcha> createState() => TurnstileCaptchaState();
}

/// State expuesto (sin guión bajo) para permitir acceso desde tests
/// vía `tester.state<TurnstileCaptchaState>(...)`.
class TurnstileCaptchaState extends State<TurnstileCaptcha> {
  TurnstileController? _controller;
  String? _currentToken;
  bool _hasError = false;
  bool _isLoading = true;
  // Cuántos timeouts seguidos hubo sin token. El primero dispara un
  // auto-reintento silencioso (red móvil lenta es la causa típica); a
  // partir del segundo recién mostramos el panel de error con botón
  // visible — así el usuario no ve un error transitorio que se cura
  // solo en 2 s.
  int _timeoutCount = 0;
  // Key incrementable que envuelve al `CloudflareTurnstile` real. Al
  // resetear, lo cambiamos para forzar que Flutter destruya y recree
  // el widget — `refreshToken()` solo sirve si Cloudflare aceptó el
  // primer paint; en timeouts duros hay que remontarlo.
  int _rebuildKey = 0;

  /// Token actual (null si aún no hay token válido o se reseteó).
  String? get currentToken => _currentToken;

  @override
  void initState() {
    super.initState();
    // Solo crear el controller real si no hay builder de test.
    if (widget.turnstileWidgetBuilder == null) {
      _controller = TurnstileController();
      _controller!.onTokenReceived(_onTokenReceived);
      _controller!.onError(_onTurnstileError);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onTokenReceived(String token) {
    if (!mounted) return;
    setState(() {
      _currentToken = token;
      _hasError = false;
      _isLoading = false;
      _timeoutCount = 0; // reset contador en éxito
    });
    widget.onToken(token);
  }

  void _onTurnstileError(TurnstileException error) {
    if (!mounted) return;
    setState(() {
      _hasError = true;
      _isLoading = false;
      _currentToken = null;
    });
    widget.onError('Error de verificación. Toque "Reintentar".');
  }

  /// Resetea el widget para que el usuario resuelva un nuevo CAPTCHA.
  /// Llamar cuando el backend rechaza el token con 400 (AC-06) o cuando
  /// el usuario toca el botón "Reintentar" del panel de error.
  void reset() {
    if (!mounted) return;
    setState(() {
      _currentToken = null;
      _hasError = false;
      _isLoading = true;
      _timeoutCount = 0;
      // Forzar remount del CloudflareTurnstile real — `refreshToken()`
      // no siempre alcanza tras un timeout duro porque el WebView ya
      // está en estado degradado. Cambiar la key garantiza un widget
      // fresco que empieza la negociación con Cloudflare de cero.
      _rebuildKey++;
    });
    _controller?.refreshToken();
  }

  // ── Métodos de prueba (test seams) ─────────────────────────────────────────

  /// Simula la recepción de un token desde el widget Turnstile.
  /// Solo se usa en widget tests — no llama a red.
  @visibleForTesting
  void simulateTokenReceived(String token) => _onTokenReceived(token);

  /// Simula un error del widget Turnstile.
  /// Solo se usa en widget tests.
  @visibleForTesting
  void simulateError(String message) {
    if (!mounted) return;
    setState(() {
      _hasError = true;
      _isLoading = false;
      _currentToken = null;
    });
    widget.onError(message);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final siteKey = widget.effectiveSiteKey;

    // Kill-switch (FR-10): sin clave → widget invisible, sin bloqueo.
    if (siteKey.isEmpty) {
      return const SizedBox.shrink();
    }

    // Si se provee un builder de test, usarlo en lugar del WebView real.
    final turnstileContent = widget.turnstileWidgetBuilder != null
        ? widget.turnstileWidgetBuilder!(this)
        : _buildRealTurnstile(siteKey);

    // ── Estado ERROR: el widget es la única fuente de verdad visual.
    // Esconde el CloudflareTurnstile (que podría seguir mostrando su
    // "Verificando seguridad…" interno) y muestra UN panel claro con
    // botón grande de Reintentar. La pantalla padre NO debe duplicar
    // este mensaje en su propio banner — su onError es solo para que
    // limpie el captcha_token.
    if (_hasError) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF4F4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppTheme.error,
                size: 32,
              ),
              const SizedBox(height: 8),
              const Text(
                'La verificación de seguridad tardó demasiado',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.error,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Toque el botón para intentarlo de nuevo.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: reset,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text(
                    'Reintentar verificación',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Loader mientras el widget de Cloudflare está cargando
        if (_isLoading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  'Verificando seguridad…',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),

        // Widget de Turnstile (real o stub de test) envuelto en KeyedSubtree
        // para que `reset()` lo remonte cuando el reintento manual lo necesita.
        KeyedSubtree(
          key: ValueKey<int>(_rebuildKey),
          child: turnstileContent,
        ),
      ],
    );
  }

  Widget _buildRealTurnstile(String siteKey) {
    return CloudflareTurnstile(
      siteKey: siteKey,
      controller: _controller,
      options: TurnstileOptions(
        language: 'es',
      ),
      onTokenReceived: _onTokenReceived,
      onError: _onTurnstileError,
      onTokenExpired: () {
        // Token expirado: resetear para que el usuario lo resuelva de nuevo.
        if (mounted) {
          setState(() {
            _currentToken = null;
            _isLoading = true;
          });
        }
      },
      onTimeout: () {
        if (!mounted) return;
        _timeoutCount++;
        if (_timeoutCount == 1) {
          // Primer timeout: reintento silencioso. Cloudflare en red
          // móvil lenta a veces necesita una segunda pasada sin
          // intervención. El usuario solo ve el loader continuar.
          setState(() {
            _isLoading = true;
            _rebuildKey++; // remount fresco
          });
          _controller?.refreshToken();
        } else {
          // Segundo timeout consecutivo: ahora sí mostrar error.
          setState(() {
            _hasError = true;
            _isLoading = false;
          });
          widget.onError('La verificación tardó demasiado.');
        }
      },
    );
  }
}
