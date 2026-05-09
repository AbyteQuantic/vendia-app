import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  ApiConfig._();

  /// Compile-time override (--dart-define=API_BASE_URL=...)
  static const _envUrl = String.fromEnvironment('API_BASE_URL');
  static const _envSupport =
      String.fromEnvironment('SUPPORT_WHATSAPP_NUMBER');

  /// Resolved base URL for all API calls.
  /// Priority: compile-time > .env > fallback per platform.
  static String get baseUrl {
    if (_envUrl.isNotEmpty) return _envUrl;

    final dotenvUrl = dotenv.maybeGet('API_BASE_URL');
    if (dotenvUrl != null && dotenvUrl.isNotEmpty) return dotenvUrl;

    // Fallback: producción detrás del custom domain (Render via
    // CNAME api.vendia.store). Si DNS aún no propaga, se puede
    // sobreescribir vía .env o --dart-define con la URL legacy
    // https://vendia-api.onrender.com.
    return 'https://api.vendia.store';
  }

  /// Customer-facing public site that serves the fiado handshake +
  /// the public catalog. Behind the CNAME `tienda.vendia.store`
  /// (Vercel). The cuaderno's "Reenviar link" share sheet builds
  /// `$publicSiteUrl/f/<token>` from this value, and the same host
  /// powers `/t/<session_token>` and `/<slug>/menu`.
  static const String publicSiteUrl = 'https://tienda.vendia.store';

  /// Builds the canonical fiado URL the cashier shares with the
  /// customer. Centralised so a future host migration only touches
  /// [publicSiteUrl] and never has to grep the codebase for hard
  /// coded `tienda.vendia.*` strings.
  static String fiadoUrlFor(String token) =>
      '$publicSiteUrl/f/$token';

  /// WhatsApp number for the "Chat por WhatsApp" secondary CTA in
  /// SupportScreen. International format without "+". Falls back to
  /// the commercial number baked into the repo so a missing env var
  /// doesn't strand the tenant with a broken link.
  static String get supportWhatsappNumber {
    if (_envSupport.isNotEmpty) return _envSupport;

    final v = dotenv.maybeGet('SUPPORT_WHATSAPP_NUMBER');
    if (v != null && v.isNotEmpty) return v;

    return '573001112233';
  }
}
