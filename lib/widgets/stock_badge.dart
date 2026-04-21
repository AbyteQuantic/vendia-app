import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Single source of truth for how stock is shown to the shopkeeper.
/// Keeping the thresholds + colour logic in one widget means that when
/// the business decides "10 is too low, bump to 15", we change it once
/// and every card updates.
///
/// Rules (gerontodesign — readable at arm's length):
///   * stock == 0   → bold red "AGOTADO" on red-tinted background
///   * stock <= 10  → amber text "Stock: N" (restock alert)
///   * stock > 10   → muted green "Stock: N" (healthy)
///
/// `unit` appends a unit label when provided ("20 botellas"); the
/// caller is responsible for pluralising so the widget stays dumb.
class StockBadge extends StatelessWidget {
  final int stock;
  final String? unit;
  final StockBadgeSize size;

  /// Threshold below or equal to which the amber "restock" colour kicks
  /// in. Exposed as a param so inventory-heavy screens can be stricter
  /// (e.g. bar/restaurant might want `lowThreshold: 5`). Defaults to the
  /// product-manager-approved value of 10.
  final int lowThreshold;

  const StockBadge({
    super.key,
    required this.stock,
    this.unit,
    this.size = StockBadgeSize.small,
    this.lowThreshold = 10,
  });

  @override
  Widget build(BuildContext context) {
    final isSoldOut = stock <= 0;
    final isLow = !isSoldOut && stock <= lowThreshold;

    final (Color fg, Color bg, String text, FontWeight weight) = switch (true) {
      _ when isSoldOut => (
          AppTheme.error,
          AppTheme.error.withValues(alpha: 0.12),
          'AGOTADO',
          FontWeight.w800,
        ),
      _ when isLow => (
          const Color(0xFFD97706), // amber-600 — high contrast on light bg
          const Color(0xFFFDBA74).withValues(alpha: 0.25),
          _formatLabel(stock, unit),
          FontWeight.w700,
        ),
      _ => (
          const Color(0xFF15803D), // green-700 — readable, not shouty
          const Color(0xFF16A34A).withValues(alpha: 0.10),
          _formatLabel(stock, unit),
          FontWeight.w600,
        ),
    };

    final (double fontSize, EdgeInsets padding) = switch (size) {
      StockBadgeSize.small => (12.0,
          const EdgeInsets.symmetric(horizontal: 8, vertical: 2)),
      StockBadgeSize.medium => (13.0,
          const EdgeInsets.symmetric(horizontal: 10, vertical: 3)),
      StockBadgeSize.large => (15.0,
          const EdgeInsets.symmetric(horizontal: 12, vertical: 5)),
    };

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: weight,
          color: fg,
          letterSpacing: isSoldOut ? 0.5 : 0,
        ),
      ),
    );
  }

  static String _formatLabel(int stock, String? unit) {
    if (unit == null || unit.isEmpty) return 'Stock: $stock';
    return 'Stock: $stock $unit';
  }
}

enum StockBadgeSize { small, medium, large }
