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
  /// `$publicSiteUrl/fiado/<token>` from this value, and the same
  /// host powers `/t/<session_token>` and `/<slug>/menu`.
  static const String publicSiteUrl = 'https://tienda.vendia.store';

  /// Builds the canonical fiado URL the cashier shares with the
  /// customer. The path matches the Next.js route at
  /// `src/app/fiado/[token]/page.tsx` in the admin-web repo.
  ///
  /// The legacy `/f/<token>` path (shipped briefly in earlier builds)
  /// is still served via a Vercel rewrite, so links already out in
  /// the wild keep working — but new shares should use the canonical
  /// path so the client's address bar matches the route they hit.
  static String fiadoUrlFor(String token) =>
      '$publicSiteUrl/fiado/$token';

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
