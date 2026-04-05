import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../onboarding_stepper_controller.dart';

/// Paso 5: Logo del negocio — generar con IA o subir desde galería.
class StepLogo extends StatefulWidget {
  const StepLogo({super.key});

  @override
  State<StepLogo> createState() => _StepLogoState();
}

class _StepLogoState extends State<StepLogo> {
  bool _generating = false;
  List<String> _logoOptions = [];
  int _selectedIndex = -1;
  String? _uploadedPath;

  Future<void> _generateLogos() async {
    setState(() {
      _generating = true;
      _logoOptions = [];
      _selectedIndex = -1;
      _uploadedPath = null;
    });

    try {
      // Logo generation requires a tenant (post-registration).
      // For onboarding, we show a preview UX and generate after registration.
      // TODO: Phase 2 — pre-registration logo endpoint
      await Future.delayed(const Duration(seconds: 3));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Los logos se generarán después del registro',
            style: TextStyle(fontSize: 16),
          ),
          backgroundColor: AppTheme.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e', style: const TextStyle(fontSize: 16)),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (photo != null && mounted) {
      setState(() {
        _uploadedPath = photo.path;
        _selectedIndex = -1;
        _logoOptions = [];
      });
      context.read<OnboardingStepperController>().logoLocalPath = photo.path;
    }
  }

  void _selectLogo(int index) {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedIndex = index;
      _uploadedPath = null;
    });
    context.read<OnboardingStepperController>().logoUrl =
        _logoOptions[index];
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<OnboardingStepperController>();
    final businessName = ctrl.businessName.isNotEmpty
        ? ctrl.businessName
        : 'su negocio';
    final typesSummary = ctrl.businessTypesSummary;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 8),

          // Motivational text
          Text(
            'Vamos a darle vida a\n$businessName',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            typesSummary.isNotEmpty
                ? 'Un logo profesional para su $typesSummary\natrae más clientes.'
                : 'Un buen logo atrae más clientes\na su catálogo virtual.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 28),

          // Logo preview circle
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.surfaceGrey,
              border: Border.all(
                color: AppTheme.borderColor,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipOval(
              child: _buildPreview(),
            ),
          ),
          const SizedBox(height: 32),

          // Logo options grid (when generated)
          if (_logoOptions.isNotEmpty) ...[
            const Text(
              'Elija el que más le guste',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_logoOptions.length, (i) {
                final isSelected = _selectedIndex == i;
                return GestureDetector(
                  onTap: () => _selectLogo(i),
                  child: Container(
                    width: 90,
                    height: 90,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primary
                            : AppTheme.borderColor,
                        width: isSelected ? 3 : 1.5,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.network(
                        _logoOptions[i],
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.broken_image_rounded,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
          ],

          // Action buttons
          if (_generating)
            Column(
              children: [
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    color: AppTheme.primary,
                    strokeWidth: 3,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  typesSummary.isNotEmpty
                      ? 'Diseñando un logo para\n$businessName ($typesSummary)...'
                      : 'Diseñando opciones exclusivas\npara $businessName...',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    color: AppTheme.textSecondary,
                    fontStyle: FontStyle.italic,
                    height: 1.4,
                  ),
                ),
              ],
            )
          else ...[
            // Generate with AI
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton.icon(
                onPressed: _generateLogos,
                icon: const Icon(Icons.auto_awesome_rounded, size: 24),
                label: const Text('Generar Logo con IA',
                    style: TextStyle(fontSize: 20)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Upload from gallery
            SizedBox(
              width: double.infinity,
              height: 64,
              child: OutlinedButton.icon(
                onPressed: _pickFromGallery,
                icon: const Icon(Icons.photo_library_rounded, size: 24),
                label: const Text('Subir foto de mi galería',
                    style: TextStyle(fontSize: 20)),
              ),
            ),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (_uploadedPath != null) {
      return Image.file(
        File(_uploadedPath!),
        fit: BoxFit.cover,
        width: 160,
        height: 160,
      );
    }
    if (_selectedIndex >= 0 && _selectedIndex < _logoOptions.length) {
      return Image.network(
        _logoOptions[_selectedIndex],
        fit: BoxFit.cover,
        width: 160,
        height: 160,
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.storefront_rounded,
            size: 56, color: AppTheme.primary.withValues(alpha: 0.3)),
        const SizedBox(height: 8),
        Text(
          'Su logo aquí',
          style: TextStyle(
            fontSize: 16,
            color: AppTheme.textSecondary.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}
