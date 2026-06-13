// Spec: specs/045-onboarding-agentic/onboarding_agentic_spec.md
//
// Smart Cards del onboarding agéntico: cada una mapea 1:1 a los campos del
// OnboardingStepperController y abre un mini-editor (bottom-sheet) tocable a
// mano. Son la red de seguridad: la IA solo las pre-rellena; la verdad es la
// card editable (degradación elegante, Art. I + II).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../services/api_service.dart';
import '../../../services/app_error.dart';
import '../../../theme/app_theme.dart';
import '../onboarding_stepper_controller.dart';

enum CardStatus { empty, confirmed }

/// Etiquetas legibles de los tipos de negocio (whitelist espejo del backend).
const Map<String, String> kBusinessTypeLabels = {
  'tienda_barrio': 'Tienda de barrio',
  'minimercado': 'Minimercado',
  'deposito_construccion': 'Depósito / Ferretería',
  'restaurante': 'Restaurante',
  'comidas_rapidas': 'Comidas rápidas',
  'bar': 'Bar / Licorera',
  'manufactura': 'Fábrica / Manufactura',
  'reparacion_muebles': 'Mueblería / Reparación',
  'emprendimiento_general': 'Emprendimiento',
  'academias_instituciones': 'Academia / Instituto',
};

/// Especificación declarativa de una Smart Card.
class CardSpec {
  CardSpec({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    required this.status,
    required this.summary,
    required this.openEditor,
  });

  final String id;
  final String title;
  final IconData icon;
  final Color color; // pastel base (se usa al 10%/30%)
  final CardStatus status;
  final String summary; // valor resumido o "Toque para llenar"
  final Future<void> Function(
      BuildContext context, OnboardingStepperController c, ApiService api) openEditor;
}

class OnboardingCards {
  static List<CardSpec> all(OnboardingStepperController c) {
    return [
      CardSpec(
        id: 'sus_datos',
        title: 'Sus datos',
        icon: Icons.person_rounded,
        color: const Color(0xFF6366F1),
        status: (c.ownerValid && c.phoneValid && c.pinValid && c.pinConfirmed)
            ? CardStatus.confirmed
            : CardStatus.empty,
        summary: c.ownerName.isNotEmpty
            ? '${c.ownerName} ${c.ownerLastName}'.trim() +
                (c.phone.isNotEmpty ? ' · ${c.phone}' : '')
            : 'Toque para llenar',
        openEditor: (ctx, ctrl, _) => _editOwner(ctx, ctrl),
      ),
      CardSpec(
        id: 'negocio',
        title: 'Su negocio',
        icon: Icons.storefront_rounded,
        color: const Color(0xFF0D9668),
        status: (c.businessNameValid && c.addressValid)
            ? CardStatus.confirmed
            : CardStatus.empty,
        summary: c.businessName.isNotEmpty
            ? c.businessName +
                (c.address.isNotEmpty ? ' · ${c.address}' : '')
            : 'Toque para llenar',
        openEditor: (ctx, ctrl, _) => _editBusiness(ctx, ctrl),
      ),
      CardSpec(
        id: 'local',
        title: '¿Uno o varios locales?',
        icon: Icons.store_mall_directory_rounded,
        color: const Color(0xFFD97706),
        status: CardStatus.confirmed, // siempre tiene valor (default: uno)
        summary: c.hasMultipleBranches ? 'Varios locales' : 'Un local',
        openEditor: (ctx, ctrl, _) => _editBranches(ctx, ctrl),
      ),
      CardSpec(
        id: 'tipo',
        title: '¿Qué vende?',
        icon: Icons.category_rounded,
        color: const Color(0xFF7C3AED),
        status: c.businessTypeSelected ? CardStatus.confirmed : CardStatus.empty,
        summary: c.businessTypeSelected
            ? (kBusinessTypeLabels[c.businessType] ?? c.businessType)
            : 'Toque para escoger',
        openEditor: (ctx, ctrl, _) => _editType(ctx, ctrl),
      ),
      CardSpec(
        id: 'logo',
        title: 'Imagen del negocio',
        icon: Icons.image_rounded,
        color: const Color(0xFF0EA5E9),
        status: c.logoSelected ? CardStatus.confirmed : CardStatus.empty,
        summary: c.logoSelected ? 'Logo listo' : 'Toque para crear o subir',
        openEditor: (ctx, ctrl, api) => _editLogo(ctx, ctrl, api),
      ),
      CardSpec(
        id: 'empleados',
        title: '¿Tiene empleados?',
        icon: Icons.groups_rounded,
        color: const Color(0xFF64748B),
        status:
            c.hasEmployees != null ? CardStatus.confirmed : CardStatus.empty,
        summary: c.hasEmployees == null
            ? 'Toque para responder'
            : (c.hasEmployees! ? 'Sí, tengo empleados' : 'Trabajo solo(a)'),
        openEditor: (ctx, ctrl, _) => _editEmployees(ctx, ctrl),
      ),
    ];
  }
}

// ─── Smart Card widget (3 estados visuales + pulso de reconocimiento) ────────
class SmartCard extends StatelessWidget {
  const SmartCard({
    super.key,
    required this.spec,
    required this.onEdit,
    this.pulsing = false,
  });

  final CardSpec spec;
  final VoidCallback onEdit;
  final bool pulsing;

  @override
  Widget build(BuildContext context) {
    final confirmed = spec.status == CardStatus.confirmed;
    final base = spec.color;
    return AnimatedScale(
      scale: pulsing ? 1.02 : 1.0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('agentic_card_${spec.id}'),
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            HapticFeedback.selectionClick();
            onEdit();
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: confirmed
                  ? base.withValues(alpha: 0.10)
                  : AppTheme.surfaceGrey,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: confirmed
                    ? base.withValues(alpha: 0.30)
                    : AppTheme.borderColor,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(spec.icon,
                    size: 24,
                    color: confirmed ? base : AppTheme.textSecondary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              spec.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          if (pulsing) ...[
                            const SizedBox(width: 8),
                            _badge('sugerido por IA ✨', base),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        spec.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          color: confirmed
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                confirmed
                    ? const Icon(Icons.check_circle_rounded,
                        size: 22, color: AppTheme.success)
                    : Icon(Icons.add_circle_outline_rounded,
                        size: 22, color: base.withValues(alpha: 0.7)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

// ─── Editores (bottom-sheets) ────────────────────────────────────────────────

Future<T?> _sheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
      ),
      child: child,
    ),
  );
}

InputDecoration _dec(String hint) => InputDecoration(hintText: hint);

Future<void> _editOwner(BuildContext context, OnboardingStepperController c) {
  return _sheet(
    context,
    StatefulBuilder(builder: (ctx, setSheet) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Sus datos',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            key: const Key('edit_owner_name'),
            controller: TextEditingController(text: c.ownerName),
            decoration: _dec('Su nombre'),
            textCapitalization: TextCapitalization.words,
            onChanged: c.setOwnerName,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: TextEditingController(text: c.ownerLastName),
            decoration: _dec('Sus apellidos'),
            textCapitalization: TextCapitalization.words,
            onChanged: c.setOwnerLastName,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('edit_owner_phone'),
            controller: TextEditingController(text: c.phone),
            decoration: _dec('Celular'),
            keyboardType: TextInputType.phone,
            onChanged: c.setPhone,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('edit_owner_pin'),
            controller: TextEditingController(text: c.pin),
            decoration: _dec('Clave (PIN de 4 a 8 números)'),
            keyboardType: TextInputType.number,
            obscureText: true,
            inputFormatters: [LengthLimitingTextInputFormatter(8)],
            onChanged: c.setPin,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('edit_owner_pin_confirm'),
            controller: TextEditingController(text: c.confirmPin),
            decoration: _dec('Repita la clave'),
            keyboardType: TextInputType.number,
            obscureText: true,
            inputFormatters: [LengthLimitingTextInputFormatter(8)],
            onChanged: c.setConfirmPin,
          ),
          const SizedBox(height: 20),
          _doneButton(ctx),
        ],
      );
    }),
  );
}

Future<void> _editBusiness(
    BuildContext context, OnboardingStepperController c) {
  return _sheet(
    context,
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Su negocio',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        TextField(
          key: const Key('edit_business_name'),
          controller: TextEditingController(text: c.businessName),
          decoration: _dec('Nombre del negocio'),
          textCapitalization: TextCapitalization.words,
          onChanged: c.setBusinessName,
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('edit_business_address'),
          controller: TextEditingController(text: c.address),
          decoration: _dec('Dirección'),
          onChanged: c.setAddress,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: TextEditingController(text: c.razonSocial),
          decoration: _dec('Razón social (opcional)'),
          onChanged: c.setRazonSocial,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: TextEditingController(text: c.nit),
          decoration: _dec('NIT (opcional)'),
          keyboardType: TextInputType.number,
          onChanged: c.setNit,
        ),
        const SizedBox(height: 20),
        _doneButton(context),
      ],
    ),
  );
}

Future<void> _editBranches(
    BuildContext context, OnboardingStepperController c) {
  return _sheet(
    context,
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('¿Uno o varios locales?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _choice(context, 'Un local', !c.hasMultipleBranches, () {
                c.setMultipleBranches(false);
                Navigator.of(context).pop();
              }),
            ),
            const SizedBox(width: 12),
            Expanded(
              child:
                  _choice(context, 'Varios locales', c.hasMultipleBranches, () {
                c.setMultipleBranches(true);
                Navigator.of(context).pop();
              }),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    ),
  );
}

Future<void> _editType(BuildContext context, OnboardingStepperController c) {
  return _sheet(
    context,
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('¿Qué vende en su negocio?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: kBusinessTypeLabels.entries.map((e) {
            final selected = c.businessType == e.key;
            return ChoiceChip(
              key: Key('type_chip_${e.key}'),
              label: Text(e.value, style: const TextStyle(fontSize: 15)),
              selected: selected,
              showCheckmark: false,
              selectedColor: AppTheme.primary,
              labelStyle: TextStyle(
                  color: selected ? Colors.white : AppTheme.textPrimary),
              backgroundColor: AppTheme.surfaceGrey,
              onSelected: (_) {
                HapticFeedback.selectionClick();
                c.setPrimaryBusinessType(e.key);
                Navigator.of(context).pop();
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
      ],
    ),
  );
}

Future<void> _editEmployees(
    BuildContext context, OnboardingStepperController c) {
  return _sheet(
    context,
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('¿Tiene empleados?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _choice(context, 'Trabajo solo(a)', c.hasEmployees == false,
                  () {
                c.setHasEmployees(false);
                Navigator.of(context).pop();
              }),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _choice(context, 'Sí, tengo', c.hasEmployees == true, () {
                c.setHasEmployees(true);
                Navigator.of(context).pop();
              }),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    ),
  );
}

Future<void> _editLogo(
    BuildContext context, OnboardingStepperController c, ApiService api) {
  return _sheet(context, _LogoEditor(controller: c, api: api));
}

Widget _choice(
    BuildContext context, String label, bool selected, VoidCallback onTap) {
  return SizedBox(
    height: 56,
    child: OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor:
            selected ? AppTheme.primary.withValues(alpha: 0.1) : null,
        side: BorderSide(
            color: selected ? AppTheme.primary : AppTheme.borderColor,
            width: selected ? 2 : 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color:
                  selected ? AppTheme.primary : AppTheme.textPrimary)),
    ),
  );
}

Widget _doneButton(BuildContext context) {
  return SizedBox(
    height: 56,
    child: ElevatedButton(
      key: const Key('sheet_done'),
      onPressed: () => Navigator.of(context).pop(),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: const Text('Listo',
          style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white)),
    ),
  );
}

// El logo necesita estado local (genera/sube con IA) → StatefulWidget.
class _LogoEditor extends StatefulWidget {
  const _LogoEditor({required this.controller, required this.api});
  final OnboardingStepperController controller;
  final ApiService api;

  @override
  State<_LogoEditor> createState() => _LogoEditorState();
}

class _LogoEditorState extends State<_LogoEditor> {
  bool _busy = false;

  Future<void> _generate() async {
    final c = widget.controller;
    if (c.businessName.trim().isEmpty || !c.businessTypeSelected) {
      _snack('Primero complete el nombre y el tipo de su negocio.');
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await widget.api.previewLogoIA(
        businessName: c.businessName,
        businessType: c.businessType,
        details: c.logoDescription.isNotEmpty
            ? c.logoDescription
            : c.businessName,
      );
      final url = (res['logo_url'] as String?)?.trim() ?? '';
      if (url.isNotEmpty && mounted) {
        c.setLogoUrl(url);
        c.suggestedLogoIntent = 'generar';
        Navigator.of(context).pop();
      } else {
        _snack('No pudimos crear el logo. Intente de nuevo.');
      }
    } on AppError catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('No pudimos crear el logo. Intente de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final res = await widget.api.previewLogoUpload(picked);
      final url = (res['logo_url'] as String?)?.trim() ?? '';
      if (url.isNotEmpty && mounted) {
        widget.controller.setLogoUrl(url);
        widget.controller.suggestedLogoIntent = 'subir';
        Navigator.of(context).pop();
      } else {
        _snack('No pudimos subir el logo. Intente de nuevo.');
      }
    } on AppError catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('No pudimos subir el logo. Intente de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: AppTheme.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Imagen de su negocio',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('Cree un logo con IA o suba el que ya tiene.',
            style: TextStyle(fontSize: 15, color: AppTheme.textSecondary)),
        const SizedBox(height: 18),
        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              key: const Key('logo_generate'),
              onPressed: _generate,
              icon: const Icon(Icons.auto_awesome, color: Colors.white),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              label: const Text('Crear logo con IA',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 56,
            child: OutlinedButton.icon(
              key: const Key('logo_upload'),
              onPressed: _upload,
              icon: const Icon(Icons.photo_library_rounded),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              label: const Text('Subir mi logo',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}
