import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../widgets/branch_selector_drawer.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/catalog_link_card.dart';
import 'ia_loading_screen.dart';
import 'create_product_screen.dart';
import 'create_service_screen.dart';
import 'manage_inventory_screen.dart';
import 'product_import_screen.dart';
import 'voice_inventory_screen.dart';
import '../pos/scan_screen.dart';
import '../suppliers/nearby_suppliers_screen.dart';
import '../suppliers/supplier_panel_screen.dart';

/// Agregar Mercancia — entry point for the inventory IA module.
/// Allows the user to photograph a supplier invoice for AI detection,
/// add products manually, or scan a barcode.
class AddMerchandiseScreen extends StatelessWidget {
  const AddMerchandiseScreen({super.key});

  /// Shows the image-source chooser (camera vs. gallery) before
  /// launching the picker. Split from [_processInvoice] so the
  /// main button stays a single tap-target while still giving
  /// tenderos with pre-taken invoices a path in — they asked for
  /// this explicitly.
  Future<void> _showImageSourceBottomSheet(BuildContext context) async {
    HapticFeedback.lightImpact();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD6D0C8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 10, 20, 8),
                child: Text(
                  '¿De dónde viene la factura?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              ListTile(
                key: const Key('invoice_source_camera'),
                leading: const Icon(Icons.camera_alt_rounded,
                    size: 32, color: Color(0xFF2563EB)),
                title: const Text(
                  'Tomar foto con la cámara',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Úselo si tiene la factura en papel frente a usted',
                  style: TextStyle(fontSize: 13),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _processInvoice(context, ImageSource.camera);
                },
              ),
              ListTile(
                key: const Key('invoice_source_gallery'),
                leading: const Icon(Icons.photo_library_rounded,
                    size: 32, color: Color(0xFF059669)),
                title: const Text(
                  'Subir foto desde la galería',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Úselo si ya le tomó foto antes o se la enviaron por WhatsApp',
                  style: TextStyle(fontSize: 13),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _processInvoice(context, ImageSource.gallery);
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  /// Launches the actual [ImagePicker] with the chosen [source],
  /// validates the payload, and routes to the AI loading screen.
  /// Unified so camera and gallery share identical validation /
  /// navigation code paths — no drift possible.
  Future<void> _processInvoice(
      BuildContext context, ImageSource source) async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: source,
      imageQuality: 75,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (photo == null || !context.mounted) return;

    // Validate file size before sending to AI
    final fileSize = await photo.length();
    const maxBytes = 5 * 1024 * 1024; // 5 MB

    if (fileSize > maxBytes) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.photo_size_select_large_rounded,
                  color: Colors.white, size: 24),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'La foto es muy pesada. Tome la foto con buena luz y un poco más de lejos.',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.warning,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IaLoadingScreen(imagePath: photo.path),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Spec 071 — SaaS Professional Density: gris nítido + lista agrupada.
      backgroundColor: AppUI.pageBg,
      appBar: AppBar(
        backgroundColor: AppUI.pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Semantics(
          button: true,
          label: 'Volver',
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppUI.ink, size: 26),
            tooltip: 'Volver',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        title: const Text('Agregar mercancía', style: AppUI.title),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: BranchSelectorChip()),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppUI.s16, AppUI.s12, AppUI.s16, AppUI.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: AppUI.s4, bottom: AppUI.s16, right: AppUI.s4),
                child: Text(
                  'Cargue su mercancía como le quede más fácil: una foto de la '
                  'factura, su voz, manual o desde Excel.',
                  style: AppUI.bodySoft,
                ),
              ),
              // Spec 071/069 — preview del catálogo en línea como ancla de la
              // vista (se oculta solo si no hay slug).
              const _CatalogPreviewLoader(),
              // Lista agrupada: un contenedor, filas con hairline (sin cajas
              // gigantes por acción). Cada fila conserva su Key y su onTap.
              InsetGroupedList(
                children: [
                  _HubActionRow(
                    rowKey: const Key('btn_read_invoice'),
                    icon: Icons.receipt_long_rounded,
                    accent: true,
                    badge: 'IA',
                    title: 'Leer factura del proveedor',
                    subtitle: 'Toque para tomar o subir la foto',
                    onTap: () => _showImageSourceBottomSheet(context),
                  ),
                  _HubActionRow(
                    rowKey: const Key('btn_voice_inventory'),
                    icon: Icons.mic_rounded,
                    accent: true,
                    badge: 'IA',
                    title: 'Dictar inventario por voz',
                    subtitle: 'Diga sus productos y la IA los organiza.',
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const VoiceInventoryScreen()));
                    },
                  ),
                  _HubActionRow(
                    icon: Icons.edit_rounded,
                    title: 'Agregar producto manualmente',
                    subtitle: 'Llene los datos uno a uno.',
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const CreateProductScreen()));
                    },
                  ),
                  _HubActionRow(
                    rowKey: const Key('add_service_button'),
                    icon: Icons.room_service_rounded,
                    title: 'Crear un servicio',
                    subtitle: 'Publíquelo en su catálogo (sin inventario).',
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const CreateServiceScreen()));
                    },
                  ),
                  _HubActionRow(
                    icon: Icons.qr_code_scanner_rounded,
                    title: 'Escanear código de barras',
                    subtitle: 'Auto-completa los datos del producto.',
                    onTap: () async {
                      HapticFeedback.lightImpact();
                      final barcode = await Navigator.of(context)
                          .push<String>(MaterialPageRoute(
                              builder: (_) => const ScanScreen()));
                      if (barcode != null &&
                          barcode.isNotEmpty &&
                          context.mounted) {
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) =>
                                CreateProductScreen(initialSku: barcode)));
                      }
                    },
                  ),
                  _HubActionRow(
                    rowKey: const Key('btn_nearby_suppliers'),
                    icon: Icons.storefront_rounded,
                    accent: true,
                    badge: 'Nuevo',
                    title: 'Proveedores cerca de usted',
                    subtitle: 'Compre directo a quien esté más cerca.',
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const NearbySuppliersScreen()));
                    },
                  ),
                  _HubActionRow(
                    icon: Icons.upload_file_rounded,
                    title: 'Importar desde Excel o CSV',
                    subtitle: 'Cargue todo su inventario de una vez.',
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const ProductImportScreen()));
                    },
                  ),
                ],
              ),
              // Spec 075 — Panel de proveedor (solo si EnableSupplierMode).
              const _SupplierPanelEntry(),
            ],
          ),
        ),
      ),
      // Acción principal fija: administrar inventario.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppUI.s16, AppUI.s8, AppUI.s16, AppUI.s16),
          child: SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ManageInventoryScreen()));
              },
              icon: const Icon(Icons.inventory_2_rounded, size: 20),
              label: const Text('Administrar inventario',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppUI.radiusSm)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Spec 075 — entrada al Panel de proveedor, visible solo si el tenant tiene
/// EnableSupplierMode (modo "Vendo a tiendas"). Self-contained: lee las flags
/// de disco y se oculta si no aplica.
class _SupplierPanelEntry extends StatefulWidget {
  const _SupplierPanelEntry();

  @override
  State<_SupplierPanelEntry> createState() => _SupplierPanelEntryState();
}

class _SupplierPanelEntryState extends State<_SupplierPanelEntry> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final flags = await AuthService().getFeatureFlags();
      if (mounted && flags.enableSupplierMode) setState(() => _show = true);
    } catch (_) {/* sin panel */}
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppUI.s16),
      child: InsetGroupedList(
        children: [
          _HubActionRow(
            rowKey: const Key('btn_supplier_panel'),
            icon: Icons.agriculture_rounded,
            accent: true,
            title: 'Panel de proveedor',
            subtitle: 'Pedidos entrantes y anti-merma.',
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const SupplierPanelScreen()));
            },
          ),
        ],
      ),
    );
  }
}

/// Spec 069/071 — carga el store_slug y muestra la tarjeta del catálogo en
/// línea en el hub. Self-contained para no convertir todo el hub en Stateful;
/// se oculta solo si no hay slug (fire-and-forget, no rompe el flujo).
class _CatalogPreviewLoader extends StatefulWidget {
  const _CatalogPreviewLoader();

  @override
  State<_CatalogPreviewLoader> createState() => _CatalogPreviewLoaderState();
}

class _CatalogPreviewLoaderState extends State<_CatalogPreviewLoader> {
  String _slug = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final cfg = await ApiService(AuthService()).fetchStoreConfig();
      final slug = (cfg['store_slug'] ?? '').toString();
      if (mounted && slug.isNotEmpty) setState(() => _slug = slug);
    } catch (_) {/* sin link; no se muestra */}
  }

  @override
  Widget build(BuildContext context) {
    if (_slug.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppUI.s16),
      child: CatalogLinkCard(
        storeSlug: _slug,
        keyPrefix: 'hub_catalog_preview',
      ),
    );
  }
}

/// Spec 071 — fila de acción del hub (densidad SaaS): tile sobrio dentro de la
/// lista agrupada, con chip de ícono, título, subtítulo de una línea y chevron.
/// Envuelve el onTap/Key existentes (solo presentación).
class _HubActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Key? rowKey;
  final bool accent;
  final String? badge;

  const _HubActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.rowKey,
    this.accent = false,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final tint = accent ? AppTheme.primary : AppUI.inkSoft;
    return InkWell(
      key: rowKey,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppUI.s16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: accent ? 0.12 : 0.06),
                borderRadius: BorderRadius.circular(AppUI.radiusSm),
              ),
              child: Icon(icon, size: 20, color: tint),
            ),
            const SizedBox(width: AppUI.s16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppUI.bodyStrong),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: AppUI.s8),
                        MinimalBadge(label: badge!, color: AppTheme.primary),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppUI.bodySoft),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppUI.inkSoft),
          ],
        ),
      ),
    );
  }
}
