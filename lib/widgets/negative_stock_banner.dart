import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/database_service.dart';
import '../theme/app_theme.dart';

/// True when a product's reserved stock exceeds physical stock.
///
/// Mirrors the Dart-side filter used by
/// [DatabaseService.watchNegativeStockProducts]; extracted so unit tests
/// can exercise the predicate without touching Isar.
bool isNegativeStock(int stock, int reservedStock) {
  return (stock - reservedStock) < 0;
}

/// Top-of-screen alert that becomes visible whenever at least one product
/// has negative available stock (i.e. reservations exceed physical stock).
///
/// Renders nothing when [count] is zero so the inventory dashboard stays
/// clean during the happy path.
class NegativeStockBanner extends StatelessWidget {
  /// Number of products currently in negative-stock state.
  final int count;

  /// Optional override for the count stream — useful for widget tests
  /// that want to drive the banner deterministically without booting Isar.
  /// When omitted the widget falls back to [count] as a static value.
  final Stream<int>? countStream;

  /// Tap handler fired when the merchant wants to regularize negative stock.
  final VoidCallback? onTap;

  const NegativeStockBanner({
    super.key,
    required this.count,
    this.countStream,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (countStream == null) {
      return _buildBanner(context, count);
    }
    return StreamBuilder<int>(
      stream: countStream,
      initialData: count,
      builder: (ctx, snap) {
        final value = snap.data ?? 0;
        return _buildBanner(ctx, value);
      },
    );
  }

  Widget _buildBanner(BuildContext context, int value) {
    if (value <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Material(
        color: AppTheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: const Key('negative_stock_banner_tap'),
          borderRadius: BorderRadius.circular(14),
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  onTap!();
                },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.error.withValues(alpha: 0.4),
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppTheme.error, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Tienes $value producto(s) con stock negativo. '
                    'Toca para regularizar',
                    key: const Key('negative_stock_banner_text'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.error,
                    ),
                  ),
                ),
                if (onTap != null)
                  const Icon(Icons.chevron_right_rounded,
                      color: AppTheme.error, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
