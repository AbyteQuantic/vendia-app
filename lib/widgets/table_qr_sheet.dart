import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// Bottom-sheet that renders the QR for a live table tab.
///
/// Flow:
///   1. Resolve the open ticket for [tableLabel] (needs at least
///      one item in the tab, otherwise the QR would point to a
///      404).
///   2. Compose the public URL as `{base_url}/t/{session_token}`.
///      The backend's `GET /store/slug` already returns a
///      `base_url` for the tenant's catalog host, so we reuse it
///      verbatim — no separate configuration needed.
///   3. Render the QR large and centered plus a share action.
///
/// Design:
///   - Self-contained (auth service + api service), so the caller
///     just invokes `showTableQrSheet(context, tableLabel: ...)`.
///   - Fail-closed: loading / empty / error states are explicit;
///     we never show a blank QR that would scan to garbage.
Future<void> showTableQrSheet(
  BuildContext context, {
  required String tableLabel,
  ApiService? apiOverride,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TableQrSheet(
      tableLabel: tableLabel,
      apiOverride: apiOverride,
    ),
  );
}

class _TableQrSheet extends StatefulWidget {
  const _TableQrSheet({
    required this.tableLabel,
    this.apiOverride,
  });

  final String tableLabel;
  final ApiService? apiOverride;

  @override
  State<_TableQrSheet> createState() => _TableQrSheetState();
}

class _TableQrSheetState extends State<_TableQrSheet> {
  _LoadState _state = const _Loading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = widget.apiOverride ?? ApiService(AuthService());
      // Two API calls in parallel keeps perceived latency low —
      // the slug endpoint is ~50 ms and open-accounts can be
      // slower depending on how many tables are active.
      final results = await Future.wait<dynamic>([
        api.fetchStoreSlug(),
        api.fetchOpenTicketByLabel(widget.tableLabel),
      ]);
      if (!mounted) return;

      final slugData = results[0] as Map<String, dynamic>;
      final ticket = results[1] as Map<String, dynamic>?;

      final baseUrl = (slugData['base_url'] as String?)?.trim();
      final token = (ticket?['session_token'] as String?)?.trim();

      if (baseUrl == null || baseUrl.isEmpty) {
        setState(() => _state = const _Error(
              'No encontramos el dominio de tu tienda. '
              'Configúralo en Marketing > Catálogo Online.',
            ));
        return;
      }
      if (ticket == null || token == null || token.isEmpty) {
        setState(() => _state = const _Empty());
        return;
      }

      // `base_url` from the backend is already the catalog root
      // (e.g. https://vendia.vercel.app/mi-tienda). The live-tab
      // route lives at the DOMAIN root, not under the slug, so we
      // chop the slug segment off before appending /t/<token>.
      final origin = _originOf(baseUrl);
      final url = '$origin/t/$token';

      setState(() => _state = _Ready(url: url, ticket: ticket));
    } catch (e) {
      if (!mounted) return;
      setState(() => _state = _Error(
            'No pudimos cargar el QR. ${e.toString()}',
          ));
    }
  }

  /// Strip any path from [raw], leaving just `scheme://host[:port]`.
  /// Falls back to the input when parsing fails so we don't silently
  /// break on an unusual value.
  String _originOf(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return raw;
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }

  Future<void> _share(String url) async {
    HapticFeedback.lightImpact();
    final text =
        '📋 Esta es tu cuenta en vivo en ${widget.tableLabel}. '
        'Ábrela cuando quieras: $url';
    await Share.share(text, subject: 'Tu cuenta en ${widget.tableLabel}');
  }

  Future<void> _copy(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Enlace copiado'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD6D0C8),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _Header(tableLabel: widget.tableLabel),
              const SizedBox(height: 18),
              _StateView(state: _state, onShare: _share, onCopy: _copy),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.tableLabel});
  final String tableLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          'Escanea para ver tu cuenta en vivo',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          tableLabel,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _StateView extends StatelessWidget {
  const _StateView({
    required this.state,
    required this.onShare,
    required this.onCopy,
  });

  final _LoadState state;
  final Future<void> Function(String url) onShare;
  final Future<void> Function(String url) onCopy;

  @override
  Widget build(BuildContext context) {
    final s = state;
    if (s is _Loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: CircularProgressIndicator(),
      );
    }
    if (s is _Empty) {
      return const _EmptyView();
    }
    if (s is _Error) {
      return _ErrorView(message: s.message);
    }
    if (s is _Ready) {
      return _ReadyView(
        url: s.url,
        onShare: () => onShare(s.url),
        onCopy: () => onCopy(s.url),
      );
    }
    return const SizedBox.shrink();
  }
}

class _ReadyView extends StatelessWidget {
  const _ReadyView({
    required this.url,
    required this.onShare,
    required this.onCopy,
  });
  final String url;
  final VoidCallback onShare;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // The QR needs high contrast; we wrap it in a generous
        // white padding so the quiet-zone is preserved even if
        // the device has a darker theme / wallpaper behind.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFEDE8E0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: QrImageView(
            key: const Key('table_qr_image'),
            data: url,
            version: QrVersions.auto,
            size: 260,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: AppTheme.primary,
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 14),
        SelectableText(
          url,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('table_qr_share'),
            onPressed: onShare,
            icon: const Icon(Icons.share_rounded),
            label: const Text('Compartir enlace'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onCopy,
            icon: const Icon(Icons.link_rounded),
            label: const Text('Copiar enlace'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(
            Icons.qr_code_2_rounded,
            size: 54,
            color: AppTheme.textSecondary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          const Text(
            'Aún no hay cuenta abierta',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Agrega el primer producto a la mesa y vuelve a tocar aquí para generar el QR.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary.withValues(alpha: 0.8),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppTheme.error, size: 46),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

sealed class _LoadState {
  const _LoadState();
}

class _Loading extends _LoadState {
  const _Loading();
}

class _Empty extends _LoadState {
  const _Empty();
}

class _Error extends _LoadState {
  const _Error(this.message);
  final String message;
}

class _Ready extends _LoadState {
  const _Ready({required this.url, required this.ticket});
  final String url;
  final Map<String, dynamic> ticket;
}
