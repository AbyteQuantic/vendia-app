import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/app_theme.dart';

/// Widget reutilizable de placeholder tipo skeleton/shimmer
class ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 16,
  });

  const ShimmerBox.full({
    super.key,
    required this.height,
    this.borderRadius = 16,
  }) : width = double.infinity;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppTheme.borderColor,
      highlightColor: const Color(0xFFF9FAFB),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

/// Skeleton completo para la tarjeta de estadística
class ShimmerStatCard extends StatelessWidget {
  const ShimmerStatCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceGrey,
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerBox(width: 52, height: 52, borderRadius: 16),
          SizedBox(height: 16),
          ShimmerBox.full(height: 18, borderRadius: 6),
          SizedBox(height: 8),
          ShimmerBox(width: 100, height: 28, borderRadius: 8),
        ],
      ),
    );
  }
}

/// Skeleton para una fila de transacción reciente
class ShimmerTransactionRow extends StatelessWidget {
  const ShimmerTransactionRow({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          ShimmerBox(width: 52, height: 52, borderRadius: 20),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox.full(height: 14, borderRadius: 6),
                SizedBox(height: 6),
                ShimmerBox(width: 80, height: 12, borderRadius: 6),
              ],
            ),
          ),
          SizedBox(width: 14),
          ShimmerBox(width: 60, height: 18, borderRadius: 6),
        ],
      ),
    );
  }
}
