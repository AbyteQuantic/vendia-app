import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/branch.dart';
import '../services/branch_provider.dart';
import '../theme/app_theme.dart';

/// Compact branch-selector chip that can be embedded in a Dashboard header
/// or AppBar. Tapping it opens a bottom sheet listing all branches.
///
/// Only visible when [BranchProvider.isMultiBranch] is true (more than one
/// active branch exists).
class BranchSelectorChip extends StatelessWidget {
  const BranchSelectorChip({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BranchProvider>();
    if (!provider.isMultiBranch) return const SizedBox.shrink();

    final branch = provider.currentBranch;
    if (branch == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _showBranchPicker(context, provider);
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: AppTheme.primary.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.store_mall_directory_rounded,
                color: AppTheme.primary, size: 16),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                branch.name,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more_rounded,
                color: AppTheme.primary, size: 16),
          ],
        ),
      ),
    );
  }

  void _showBranchPicker(BuildContext context, BranchProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFD6D0C8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'Seleccionar Sede',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87),
            ),
            const SizedBox(height: 16),
            ...provider.branches
                .where((b) => b.isActive)
                .map((b) => _BranchPickerTile(
                      branch: b,
                      isSelected:
                          provider.currentBranch?.id == b.id,
                      onTap: () {
                        provider.selectBranch(b);
                        Navigator.of(ctx).pop();
                      },
                    )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _BranchPickerTile extends StatelessWidget {
  final Branch branch;
  final bool isSelected;
  final VoidCallback onTap;

  const _BranchPickerTile({
    required this.branch,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primary.withValues(alpha: 0.06)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? AppTheme.primary
                  : const Color(0xFFE8E4DF),
              width: isSelected ? 2 : 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                branch.isDefault
                    ? Icons.home_work_rounded
                    : Icons.store_mall_directory_rounded,
                color: isSelected
                    ? AppTheme.primary
                    : AppTheme.textSecondary,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      branch.name,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? AppTheme.primary
                            : Colors.black87,
                      ),
                    ),
                    if (branch.address != null &&
                        branch.address!.isNotEmpty)
                      Text(
                        branch.address!,
                        style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(Icons.check_circle_rounded,
                    color: AppTheme.success, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
