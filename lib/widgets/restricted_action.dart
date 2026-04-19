import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Show a Gerontodiseño-friendly "Sin permiso" modal. Use whenever a
/// cashier or restricted role taps something that their JWT role doesn't
/// allow. The dialog never blocks — merchants can always close it — but it
/// explains WHY the action didn't happen so they aren't left guessing.
Future<void> showRestrictedActionDialog(
  BuildContext context, {
  String title = 'Sin permiso',
  String message =
      'Esta opción solo la puede usar el propietario del negocio.',
  String actionLabel = 'Entendido',
}) async {
  HapticFeedback.mediumImpact();
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.lock_outline_rounded,
              color: AppTheme.primary, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      content: Text(
        message,
        style: const TextStyle(fontSize: 18, height: 1.3),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 4),
          child: TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(actionLabel,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    ),
  );
}

/// Wraps a child so that taps are intercepted when [allowed] is false and
/// a "Sin permiso" dialog is shown instead of running [onTap].
class RestrictedAction extends StatelessWidget {
  const RestrictedAction({
    super.key,
    required this.allowed,
    required this.onTap,
    required this.child,
    this.deniedMessage,
  });

  final bool allowed;
  final VoidCallback onTap;
  final Widget child;
  final String? deniedMessage;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        if (allowed) {
          onTap();
        } else {
          showRestrictedActionDialog(
            context,
            message: deniedMessage ??
                'Esta opción solo la puede usar el propietario del negocio.',
          );
        }
      },
      child: child,
    );
  }
}
