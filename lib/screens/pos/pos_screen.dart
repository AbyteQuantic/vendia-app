import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../../models/cart_item.dart';
import '../../models/product.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panic_button.dart';
import '../../widgets/sync_status_banner.dart';
import 'cart_controller.dart';
import 'account_qr_screen.dart';
import 'widgets/container_dialog.dart';
import 'scan_screen.dart';
import 'checkout_screen.dart';
import 'sale_success_screen.dart';
import 'cuaderno_fiados_screen.dart';
import '../../database/database_service.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../database/collections/local_sale.dart';
import '../inventory/add_merchandise_screen.dart';

/// PosScreen — Mobile-First POS with persistent bottom bar.
/// Products fill the screen; cart opens as a bottom sheet.
class PosScreen extends StatelessWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CartController(),
      child: const _PosScreenBody(),
    );
  }
}

class _PosScreenBody extends StatefulWidget {
  const _PosScreenBody();

  @override
  State<_PosScreenBody> createState() => _PosScreenBodyState();
}

class _PosScreenBodyState extends State<_PosScreenBody> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _tables = [];

  @override
  void initState() {
    super.initState();
    _loadTables();
  }

  Future<void> _loadTables() async {
    try {
      final api = ApiService(AuthService());
      final tables = await api.fetchTables();
      if (mounted) setState(() => _tables = tables);
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _addProductWithContainerCheck(
      CartController ctrl, Product product) async {
    if (product.requiresContainer && product.containerPrice > 0) {
      final choice = await showDialog<ContainerChoice>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ContainerDialog(product: product),
      );
      if (choice == null) return;
      ctrl.addProduct(product);
      if (choice == ContainerChoice.notBrought) {
        ctrl.addContainerCharge(product);
      }
    } else {
      ctrl.addProduct(product);
    }
  }

  void _showCartSheet(CartController ctrl) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider.value(
        value: ctrl,
        child: const _CartBottomSheet(),
      ),
    );
  }

  void _showProductDetailModal(Product product, CartController ctrl) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ProductDetailSheet(
        product: product,
        onAddToCart: () {
          Navigator.of(ctx).pop();
          _addProductWithContainerCheck(ctrl, product);
        },
      ),
    );
  }

  // ── Context Sheet: "¿Para quién es esta cuenta?" ──────────────────────────
  void _showContextSheet(CartController ctrl) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AccountContextSheet(
        onMostrador: () {
          ctrl.setContext(const AccountContext(type: AccountType.mostrador));
          Navigator.of(context).pop();
        },
        onMesa: () {
          Navigator.of(context).pop();
          _showMesaSelector(ctrl, AccountType.mesa);
        },
        onMesaInmediata: () {
          Navigator.of(context).pop();
          _showMesaSelector(ctrl, AccountType.mesaInmediata);
        },
        onFiado: () {
          Navigator.of(context).pop();
          _showFiadoSelector(ctrl);
        },
      ),
    );
  }

  void _showMesaSelector(CartController ctrl, AccountType mesaType) {
    final isImmediate = mesaType == AccountType.mesaInmediata;
    final accentColor = isImmediate ? const Color(0xFFEA580C) : AppTheme.primary;
    final subtitle = isImmediate ? 'Pago inmediato' : 'Cuenta abierta';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFD6D0C8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text('Seleccionar Mesa',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle,
                style: TextStyle(fontSize: 15, color: accentColor,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            _tables.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No hay mesas configuradas.\nVaya a Mi Negocio > Gestión de Mesas.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
                    ),
                  )
                : GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.3,
                    ),
                    itemCount: _tables.length,
                    itemBuilder: (_, i) {
                      final t = _tables[i];
                      final label = t['label'] as String? ?? 'Mesa ${i + 1}';
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          ctrl.setContext(AccountContext(
                            type: mesaType,
                            tableLabel: label,
                          ));
                          Navigator.of(context).pop();
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                          ),
                          alignment: Alignment.center,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.table_restaurant_rounded,
                                      color: accentColor, size: 24),
                                  const SizedBox(height: 2),
                                  Text(label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 13, fontWeight: FontWeight.bold,
                                          color: accentColor)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }

  void _showFiadoSelector(CartController ctrl) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD6D0C8),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Row(
                children: [
                  Text('📓', style: TextStyle(fontSize: 28)),
                  SizedBox(width: 10),
                  Text('Fiar a un Cliente',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                style: const TextStyle(fontSize: 18),
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'Nombre del cliente',
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                  prefixIcon: const Icon(Icons.person_rounded,
                      color: AppTheme.primary),
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 16, horizontal: 16),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                style: const TextStyle(fontSize: 18),
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: 'Celular (para WhatsApp)',
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                  prefixIcon: const Icon(Icons.phone_rounded,
                      color: AppTheme.primary),
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 16, horizontal: 16),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  HapticFeedback.mediumImpact();
                  ctrl.setContext(AccountContext(
                    type: AccountType.fiado,
                    customerName: name,
                    customerPhone: phoneCtrl.text.trim(),
                  ));
                  Navigator.of(ctx).pop();
                },
                icon: const Icon(Icons.check_rounded, size: 24),
                label: const Text('Asignar Cliente',
                    style: TextStyle(fontSize: 20)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6D28D9),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(64),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Smart Action Button Handler ──────────────────────────────────────────
  void _handleSmartAction(CartController ctrl) {
    HapticFeedback.heavyImpact();
    switch (ctrl.activeContext.type) {
      case AccountType.mostrador:
        _cobrarMostrador(ctrl);
        break;
      case AccountType.mesa:
        _sendOrder(ctrl);
        break;
      case AccountType.mesaInmediata:
        _cobrarYEnviar(ctrl);
        break;
      case AccountType.fiado:
        _registerFiado(ctrl);
        break;
    }
  }

  Future<void> _syncSaleToBackend(
      List<CartItem> cartItems, String paymentMethod, String saleUuid) async {
    try {
      final api = ApiService(AuthService());
      await api.createSale({
        'id': saleUuid,
        'payment_method': paymentMethod,
        'items': cartItems.map((item) => {
                  'product_id': item.product.uuid.isNotEmpty
                      ? item.product.uuid
                      : item.product.id.toString(),
                  'quantity': item.quantity,
                })
            .toList(),
      });
      // Mark as synced in Isar
      final db = DatabaseService.instance;
      final allSales = await db.getSalesToday();
      final match = allSales.where((s) => s.uuid == saleUuid).toList();
      if (match.isNotEmpty) {
        await db.isar.writeTxn(() async {
          match.first.synced = true;
          await db.isar.localSales.put(match.first);
        });
      }
    } catch (e) {
      debugPrint('SALE SYNC ERROR (will retry later): $e');
    }
  }

  void _cobrarMostrador(CartController ctrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(
          items: ctrl.activeCart,
          formattedTotal: ctrl.formattedTotal,
          total: ctrl.activeTotal,
        ),
      ),
    ).then((result) async {
      if (result is CheckoutResult && result.confirmed) {
        // Capture total BEFORE clearing cart
        final saleTotal = ctrl.activeTotal;
        final saleTotalFormatted = _formatCOP(saleTotal.round());

        // Process sale: save to Isar + deduct stock
        final db = DatabaseService.instance;
        final saleUuid = const Uuid().v4();
        final saleItems = ctrl.activeCart.map((item) {
          return SaleItemEmbed()
            ..productUuid = item.product.uuid.isNotEmpty
                ? item.product.uuid
                : item.product.id.toString()
            ..productName = item.product.name
            ..quantity = item.quantity
            ..unitPrice = item.product.price
            ..isContainerCharge = false;
        }).toList();

        final employeeName = await AuthService().getOwnerName() ?? '';
        final localSale = LocalSale()
          ..uuid = saleUuid
          ..total = saleTotal
          ..paymentMethod = result.paymentMethod
          ..employeeName = employeeName
          ..isCreditSale = result.paymentMethod == 'credit'
          ..items = saleItems
          ..createdAt = DateTime.now()
          ..synced = false;

        await db.insertSaleAndDeductStock(localSale);

        // Copy cart items BEFORE clearing (List is reference type)
        final cartSnapshot = List<CartItem>.from(ctrl.activeCart);

        ctrl.clearActiveCart();

        // Sync sale to backend (fire and forget — don't block UX)
        _syncSaleToBackend(cartSnapshot, result.paymentMethod, saleUuid);

        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SaleSuccessScreen(
              total: saleTotalFormatted,
              paymentMethod: result.paymentMethod,
            ),
          ),
        );
      }
    });
  }

  String _formatCOP(int amount) {
    final s = amount.toString();
    final buffer = StringBuffer('\$');
    final start = s.length % 3;
    if (start > 0) buffer.write(s.substring(0, start));
    for (int i = start; i < s.length; i += 3) {
      if (i > 0) buffer.write('.');
      buffer.write(s.substring(i, i + 3));
    }
    return buffer.toString();
  }

  void _sendOrder(CartController ctrl) {
    final ctx = ctrl.activeContext;
    // TODO: persist order to local DB / API
    // Keep mesa assigned, only clear items
    ctrl.clearCartKeepContext();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '🛎️ Pedido enviado a ${ctx.tableLabel}',
          style: const TextStyle(fontSize: 16),
        ),
        backgroundColor: AppTheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    // Auto-navigate to next empty tab
    final next = ctrl.nextEmptyIndex;
    if (next != -1 && next != ctrl.activeIndex) {
      ctrl.switchCart(next);
    }
  }

  void _cobrarYEnviar(CartController ctrl) {
    final ctx = ctrl.activeContext;
    // Show payment method picker, then process
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFD6D0C8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              'Cobrar y enviar a ${ctx.tableLabel}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(
              ctrl.formattedTotal,
              style: const TextStyle(
                  fontSize: 28, fontWeight: FontWeight.bold,
                  color: Color(0xFF0D9668)),
            ),
            const SizedBox(height: 20),
            for (final method in [
              ('Efectivo', Icons.payments_rounded, const Color(0xFF10B981)),
              ('Nequi', Icons.phone_android_rounded, const Color(0xFF6D28D9)),
              ('Daviplata', Icons.phone_android_rounded, const Color(0xFFDC2626)),
              ('Tarjeta', Icons.credit_card_rounded, const Color(0xFF3B82F6)),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.heavyImpact();
                    Navigator.of(sheetCtx).pop();
                    // TODO: persist sale with table_id + payment method to DB/API
                    // TODO: send KDS notification for table
                    ctrl.clearActiveCart();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '✅ Cobrado con ${method.$1} y enviado a ${ctx.tableLabel}',
                          style: const TextStyle(fontSize: 16),
                        ),
                        backgroundColor: const Color(0xFF0D9668),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    height: 60,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: method.$3.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: method.$3.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        Icon(method.$2, color: method.$3, size: 28),
                        const SizedBox(width: 14),
                        Text(method.$1,
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold,
                                color: method.$3)),
                        const Spacer(),
                        Icon(Icons.chevron_right_rounded,
                            color: method.$3, size: 24),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _registerFiado(CartController ctrl) {
    final ctx = ctrl.activeContext;
    final total = ctrl.formattedTotal;
    final items = ctrl.activeCart
        .map((i) => '• ${i.product.name} x${i.quantity} = ${i.formattedSubtotal}')
        .join('\n');

    // TODO: persist credit to local DB / API
    ctrl.clearActiveCart();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dlgCtx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Column(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: Color(0xFF10B981), size: 56),
            const SizedBox(height: 10),
            Text(
              '¡Fiado anotado a\n${ctx.customerName}!',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Total: $total',
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold,
                    color: Color(0xFF6D28D9))),
            const SizedBox(height: 20),
            if (ctx.customerPhone != null && ctx.customerPhone!.isNotEmpty)
              SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final phone = ctx.customerPhone!.replaceAll(RegExp(r'[^0-9]'), '');
                    final fullPhone = phone.startsWith('57') ? phone : '57$phone';
                    final msg = Uri.encodeComponent(
                      'Hola ${ctx.customerName}, este es el detalle de su fiado:\n\n'
                      '$items\n\n'
                      'Total: $total\n\n'
                      'Puede ver su saldo pendiente en:\n'
                      'https://tienda.vendia.app/deuda/${ctrl.activeIndex}',
                    );
                    launchUrl(
                      Uri.parse('https://wa.me/$fullPhone?text=$msg'),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  icon: const Icon(Icons.message_rounded, size: 24),
                  label: const Text('Enviar por WhatsApp',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dlgCtx).pop(),
            child: const Text('Cerrar', style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CartController>(
      builder: (context, ctrl, _) {
        if (!ctrl.productsLoaded) {
          return const Scaffold(
            backgroundColor: AppTheme.background,
            body: Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            ),
          );
        }

        if (!ctrl.hasRealProducts) {
          return _EmptyInventoryGuide(
            onAddInventory: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AddMerchandiseScreen(),
                ),
              );
            },
            onGoBack: () => Navigator.of(context).pop(),
          );
        }

        final cartItemCount =
            ctrl.activeCart.fold(0, (sum, i) => sum + i.quantity);

        return Scaffold(
          backgroundColor: const Color(0xFFFFFBF7),
          body: SafeArea(
            child: Column(
              children: [
                // ── AppBar ──
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: AppTheme.textPrimary, size: 28),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Vender',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      PanicButton(onPanicTriggered: () {
                        ApiService(AuthService()).triggerPanic();
                      }),
                      const SizedBox(width: 6),
                      _HeaderBadgeIcon(
                        icon: Icons.menu_book_rounded,
                        badgeCount: 0,
                        badgeColor: const Color(0xFF6D28D9),
                        onPressed: () async {
                          HapticFeedback.lightImpact();
                          final result = await Navigator.of(context).push<Map<String, String>>(
                            MaterialPageRoute(
                              builder: (_) => const CuadernoFiadosScreen(),
                            ),
                          );
                          // Handle "Fiar más" return
                          if (result != null && result['action'] == 'fiar_mas') {
                            ctrl.assignFiadoToTab(
                              result['name'] ?? '',
                              result['phone'] ?? '',
                            );
                          }
                        },
                      ),
                      const SizedBox(width: 6),
                      _HeaderBadgeIcon(
                        icon: Icons.notifications_rounded,
                        badgeCount: 2,
                        badgeColor: const Color(0xFFFF6B6B),
                        onPressed: () => HapticFeedback.lightImpact(),
                      ),
                    ],
                  ),
                ),

                const SyncStatusBanner(),

                // ── Cart tabs ──
                _CartTabs(
                  activeIndex: ctrl.activeIndex,
                  onTabSelected: ctrl.switchCart,
                  onActiveTabTapped: () => _showContextSheet(ctrl),
                  cartCounts: List.generate(10, ctrl.cartCount),
                  contexts: List.generate(10, ctrl.contextAt),
                ),

                // ── Search ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(fontSize: 18),
                    onChanged: ctrl.setSearch,
                    decoration: InputDecoration(
                      hintText: 'Buscar producto...',
                      hintStyle: const TextStyle(
                          fontSize: 18, color: Color(0xFF9CA3AF)),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: Color(0xFF9CA3AF), size: 24),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ValueListenableBuilder(
                            valueListenable: _searchCtrl,
                            builder: (_, value, __) => value.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close_rounded,
                                        color: AppTheme.textSecondary),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      ctrl.setSearch('');
                                    },
                                  )
                                : const SizedBox.shrink(),
                          ),
                          IconButton(
                            icon: const Icon(Icons.qr_code_scanner_rounded,
                                color: AppTheme.primary, size: 24),
                            tooltip: 'Escanear código de barras',
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ScanScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8F7F5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                    ),
                  ),
                ),

                // ── Product Grid (full width!) ──
                Expanded(
                  child: _buildProductGrid(ctrl),
                ),
              ],
            ),
          ),

          // ── Persistent Bottom Bar ──
          bottomNavigationBar: _BottomBar(
            total: ctrl.formattedTotal,
            itemCount: cartItemCount,
            activeIndex: ctrl.activeIndex,
            hasItems: ctrl.activeCart.isNotEmpty,
            context_: ctrl.activeContext,
            onTapCart: () => _showCartSheet(ctrl),
            onAction: () => _handleSmartAction(ctrl),
            onQr: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AccountQrScreen(
                    accountLabel: 'C${ctrl.activeIndex + 1}',
                    cartLabel: 'Cuenta Activa',
                    accountUuid: 'cuenta-${ctrl.activeIndex}',
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildProductGrid(CartController ctrl) {
    final products = ctrl.filteredProducts;
    if (products.isEmpty) {
      return const Center(
        child: Text('Sin resultados',
            style: TextStyle(fontSize: 18, color: AppTheme.textSecondary)),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemCount: products.length,
      itemBuilder: (_, i) {
        final product = products[i];
        return Consumer<CartController>(
          builder: (_, c, __) {
            final qty = c.getQuantity(product);
            return _ProductCard(
              product: product,
              quantity: qty,
              onTap: () => _addProductWithContainerCheck(c, product),
              onLongPress: () => _showProductDetailModal(product, c),
              onIncrement: () {
                HapticFeedback.lightImpact();
                c.addProduct(product);
              },
              onDecrement: () {
                HapticFeedback.lightImpact();
                c.decrement(product);
              },
            );
          },
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PRODUCT CARD — overflow-proof, uses LayoutBuilder
// ═══════════════════════════════════════════════════════════════════════════════

class _ProductCard extends StatelessWidget {
  final Product product;
  final int quantity;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  const _ProductCard({
    required this.product,
    required this.quantity,
    required this.onTap,
    required this.onLongPress,
    required this.onIncrement,
    required this.onDecrement,
  });

  @override
  Widget build(BuildContext context) {
    final inCart = quantity > 0;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: inCart
              ? Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.5), width: 2)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: LayoutBuilder(
          builder: (context, box) {
            // Split: 50% image, 50% content — guaranteed no overflow
            final imageH = (box.maxHeight * 0.50).roundToDouble();
            final contentH = box.maxHeight - imageH;

            return Column(
              children: [
                // ── Image ──
                SizedBox(
                  height: imageH,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildImage(imageH),
                      if (inCart)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$quantity',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // ── Content ──
                SizedBox(
                  height: contentH,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name + subtitle (flexible — absorbs overflow)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                  height: 1.2,
                                ),
                              ),
                              if (product.subtitle.isNotEmpty)
                                Text(
                                  product.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                    height: 1.3,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        // Price row (fixed height)
                        SizedBox(
                          height: 30,
                          child: Row(
                            children: [
                              Text(
                                product.formattedPrice,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primary,
                                ),
                              ),
                              const Spacer(),
                              if (inCart) ...[
                                _miniButton(
                                  icon: quantity == 1
                                      ? Icons.delete_outline_rounded
                                      : Icons.remove_rounded,
                                  color: quantity == 1
                                      ? AppTheme.error
                                      : AppTheme.textPrimary,
                                  bg: AppTheme.surfaceGrey,
                                  onTap: onDecrement,
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6),
                                  child: Text(
                                    '$quantity',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                _miniButton(
                                  icon: Icons.add_rounded,
                                  color: Colors.white,
                                  bg: AppTheme.primary,
                                  onTap: onIncrement,
                                ),
                              ] else
                                _miniButton(
                                  icon: Icons.add_rounded,
                                  color: Colors.white,
                                  bg: AppTheme.primary,
                                  onTap: onTap,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildImage(double h) {
    final url = product.imageUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        height: h,
        width: double.infinity,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _placeholder(h),
        loadingBuilder: (_, child, p) => p == null ? child : _placeholder(h),
      );
    }
    return _placeholder(h);
  }

  Widget _placeholder(double h) {
    return Container(
      height: h,
      color: const Color(0xFFF0F4FF),
      child: const Center(
        child: Icon(Icons.inventory_2_rounded,
            color: AppTheme.primary, size: 32),
      ),
    );
  }

  Widget _miniButton({
    required IconData icon,
    required Color color,
    required Color bg,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PERSISTENT BOTTOM BAR
// ═══════════════════════════════════════════════════════════════════════════════

class _BottomBar extends StatelessWidget {
  final String total;
  final int itemCount;
  final int activeIndex;
  final bool hasItems;
  final AccountContext context_;
  final VoidCallback onTapCart;
  final VoidCallback onAction;
  final VoidCallback onQr;

  const _BottomBar({
    required this.total,
    required this.itemCount,
    required this.activeIndex,
    required this.hasItems,
    required this.context_,
    required this.onTapCart,
    required this.onAction,
    required this.onQr,
  });

  // Smart button config based on account context
  _SmartButton get _button {
    switch (context_.type) {
      case AccountType.mostrador:
        return _SmartButton(
          label: hasItems ? '💰 COBRAR $total' : 'COBRAR',
          gradient: const [Color(0xFF0D9668), Color(0xFF10B981)],
        );
      case AccountType.mesa:
        return _SmartButton(
          label: hasItems ? '🛎️ ENVIAR $total' : 'ENVIAR PEDIDO',
          gradient: const [Color(0xFF1A56DB), Color(0xFF3B82F6)],
        );
      case AccountType.mesaInmediata:
        return _SmartButton(
          label: hasItems ? '💰 COBRAR Y ENVIAR $total' : 'COBRAR Y ENVIAR',
          gradient: const [Color(0xFF0D9668), Color(0xFF10B981)],
        );
      case AccountType.fiado:
        return _SmartButton(
          label: hasItems ? '📓 FIAR $total' : 'ANOTAR FIADO',
          gradient: const [Color(0xFF6D28D9), Color(0xFF8B5CF6)],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final btn = _button;
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, MediaQuery.of(context).padding.bottom + 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Cart summary (tappable to open sheet)
          GestureDetector(
            onTap: hasItems ? onTapCart : null,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F7F5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Badge(
                    label: Text('$itemCount',
                        style: const TextStyle(fontSize: 11)),
                    isLabelVisible: itemCount > 0,
                    child: const Icon(Icons.shopping_cart_outlined,
                        size: 24, color: AppTheme.textPrimary),
                  ),
                  if (hasItems) ...[
                    const SizedBox(width: 8),
                    Text(
                      total,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(width: 10),

          // QR
          if (hasItems)
            GestureDetector(
              onTap: onQr,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.qr_code_2_rounded,
                    size: 24, color: AppTheme.primary),
              ),
            ),

          if (hasItems) const SizedBox(width: 10),

          // Smart Action Button
          Expanded(
            child: GestureDetector(
              onTap: hasItems ? onAction : null,
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  gradient: hasItems
                      ? LinearGradient(colors: btn.gradient)
                      : null,
                  color: hasItems ? null : const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: Text(
                  btn.label,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: hasItems ? Colors.white : const Color(0xFF999999),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmartButton {
  final String label;
  final List<Color> gradient;
  const _SmartButton({required this.label, required this.gradient});
}

// ═══════════════════════════════════════════════════════════════════════════════
// CART BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════════════════

class _CartBottomSheet extends StatelessWidget {
  const _CartBottomSheet();

  @override
  Widget build(BuildContext context) {
    return Consumer<CartController>(
      builder: (context, ctrl, _) {
        final items = ctrl.activeCart;
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD6D0C8),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Row(
                  children: [
                    Text(
                      'Cuenta C${ctrl.activeIndex + 1}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    if (items.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          ctrl.clearActiveCart();
                          Navigator.of(context).pop();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.error.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Limpiar',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.error,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Items
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Icon(Icons.shopping_cart_outlined,
                          size: 48, color: Color(0xFFD6D0C8)),
                      SizedBox(height: 12),
                      Text('Carrito vacío',
                          style: TextStyle(
                              fontSize: 18, color: AppTheme.textSecondary)),
                    ],
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final item = items[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F7F5),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            // Name + price
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.product.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.formattedSubtotal,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Quantity controls (60px buttons for gerontodiseño)
                            _cartQtyButton(
                              icon: item.quantity == 1
                                  ? Icons.delete_outline_rounded
                                  : Icons.remove_rounded,
                              color: item.quantity == 1
                                  ? AppTheme.error
                                  : AppTheme.textSecondary,
                              onTap: () {
                                HapticFeedback.lightImpact();
                                ctrl.decrement(item.product);
                              },
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12),
                              child: Text(
                                '${item.quantity}',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            _cartQtyButton(
                              icon: Icons.add_rounded,
                              color: Colors.white,
                              bg: AppTheme.primary,
                              onTap: () {
                                HapticFeedback.lightImpact();
                                ctrl.increment(item.product);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

              // Total
              if (items.isNotEmpty)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      20, 8, 20, MediaQuery.of(context).padding.bottom + 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      Text(
                        ctrl.formattedTotal,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _cartQtyButton({
    required IconData icon,
    required Color color,
    Color bg = const Color(0xFFF3F0EC),
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, size: 22, color: color),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CART TABS
// ═══════════════════════════════════════════════════════════════════════════════

class _CartTabs extends StatelessWidget {
  final int activeIndex;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onActiveTabTapped;
  final List<int> cartCounts;
  final List<AccountContext> contexts;

  const _CartTabs({
    required this.activeIndex,
    required this.onTabSelected,
    required this.onActiveTabTapped,
    required this.cartCounts,
    required this.contexts,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: cartCounts.length,
        itemBuilder: (_, i) {
          final isActive = activeIndex == i;
          final count = cartCounts[i];
          final hasItems = count > 0 && !isActive;
          final ctx = contexts[i];
          final hasContext = ctx.type != AccountType.mostrador;
          // Occupied = has context but empty cart (sent to kitchen, waiting)
          final isOccupied = hasContext && count == 0 && !isActive;

          // Tab label: context name or default "C{n}"
          final label = hasContext ? ctx.tabLabel : 'C${i + 1}';
          // Truncate long labels
          final displayLabel =
              label.length > 7 ? '${label.substring(0, 6)}…' : label;

          // Color coding by context
          List<Color>? gradient;
          if (isActive) {
            switch (ctx.type) {
              case AccountType.mostrador:
                gradient = const [Color(0xFF1A2FA0), Color(0xFF2541B2)];
                break;
              case AccountType.mesa:
                gradient = const [Color(0xFF1A56DB), Color(0xFF3B82F6)];
                break;
              case AccountType.mesaInmediata:
                gradient = const [Color(0xFFEA580C), Color(0xFFF97316)];
                break;
              case AccountType.fiado:
                gradient = const [Color(0xFF6D28D9), Color(0xFF8B5CF6)];
                break;
            }
          }

          // Dynamic width: wider for context labels
          final tabWidth = hasContext ? 72.0 : 48.0;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                if (isActive) {
                  onActiveTabTapped();
                } else {
                  onTabSelected(i);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: tabWidth,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: isActive ? LinearGradient(colors: gradient!) : null,
                  color: isActive
                      ? null
                      : isOccupied
                          ? const Color(0xFFE8F0FE)
                          : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: hasItems
                      ? Border.all(color: const Color(0xFFF59E0B), width: 2)
                      : isOccupied
                          ? Border.all(color: const Color(0xFF3B82F6), width: 1.5)
                          : null,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Occupied dot indicator (top-right)
                    if (isOccupied)
                      const Positioned(
                        top: -3, right: -3,
                        child: CircleAvatar(
                          radius: 5,
                          backgroundColor: Color(0xFF3B82F6),
                          child: Icon(Icons.restaurant_rounded,
                              size: 7, color: Colors.white),
                        ),
                      ),
                    Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            displayLabel,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: hasContext ? 11 : 13,
                              fontWeight: FontWeight.w800,
                              color: isActive
                                  ? Colors.white
                                  : (hasItems || isOccupied)
                                      ? AppTheme.textPrimary
                                      : const Color(0xFFBBBBBB),
                            ),
                          ),
                        ),
                        if (isActive)
                          Icon(Icons.keyboard_arrow_down_rounded,
                              size: 14,
                              color: Colors.white.withValues(alpha: 0.85)),
                      ],
                    ),
                    if (isActive && !hasContext)
                      Text(
                        'Activa',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    if (hasItems)
                      Text(
                        '$count',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                  ],
                ),
                    ), // Center
                  ], // Stack children
                ), // Stack
              ),
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ACCOUNT CONTEXT SHEET — "¿Para quién es esta cuenta?"
// ═══════════════════════════════════════════════════════════════════════════════

class _AccountContextSheet extends StatelessWidget {
  final VoidCallback onMostrador;
  final VoidCallback onMesa;
  final VoidCallback onFiado;
  final VoidCallback onMesaInmediata;

  const _AccountContextSheet({
    required this.onMostrador,
    required this.onMesa,
    required this.onFiado,
    required this.onMesaInmediata,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFD6D0C8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              '¿Para quién es esta cuenta?',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // Option A: Mostrador
            _ContextOption(
              icon: Icons.shopping_cart_rounded,
              emoji: '🛒',
              label: 'Venta de Mostrador',
              subtitle: 'Cobro rápido al momento',
              color: const Color(0xFF10B981),
              onTap: onMostrador,
            ),
            const SizedBox(height: 12),

            // Option B: Mesa (cuenta abierta)
            _ContextOption(
              icon: Icons.table_restaurant_rounded,
              emoji: '🍽️',
              label: 'Asignar a Mesa',
              subtitle: 'Cuenta abierta, cobro al final',
              color: const Color(0xFF3B82F6),
              onTap: onMesa,
            ),
            const SizedBox(height: 12),

            // Option C: Mesa (pago inmediato)
            _ContextOption(
              icon: Icons.receipt_long_rounded,
              emoji: '💳',
              label: 'Mesa (Pago Inmediato)',
              subtitle: 'Pagan cada ronda al instante',
              color: const Color(0xFFEA580C),
              onTap: onMesaInmediata,
            ),
            const SizedBox(height: 12),

            // Option D: Fiado
            _ContextOption(
              icon: Icons.menu_book_rounded,
              emoji: '📓',
              label: 'Fiar a un Cliente',
              subtitle: 'Anotar en el cuaderno',
              color: const Color(0xFF6D28D9),
              onTap: onFiado,
            ),
          ],
        ),
      ),
    );
  }
}

class _ContextOption extends StatelessWidget {
  final IconData icon;
  final String emoji;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ContextOption({
    required this.icon,
    required this.emoji,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: color)),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 15, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: color, size: 28),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PRODUCT DETAIL SHEET
// ═══════════════════════════════════════════════════════════════════════════════

class _ProductDetailSheet extends StatelessWidget {
  final Product product;
  final VoidCallback onAddToCart;

  const _ProductDetailSheet({
    required this.product,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD6D0C8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: (product.imageUrl != null && product.imageUrl!.isNotEmpty)
                  ? Image.network(product.imageUrl!,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.contain)
                  : Container(
                      height: 200,
                      color: const Color(0xFFF0F4FF),
                      child: const Center(
                        child: Icon(Icons.inventory_2_rounded,
                            color: AppTheme.primary, size: 48),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(
              product.name,
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              product.formattedPrice,
              style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color:
                        product.stock > 0 ? AppTheme.success : AppTheme.error,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  product.stock > 0
                      ? '${product.stock} en stock'
                      : 'Sin stock',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: product.stock > 0
                        ? AppTheme.textSecondary
                        : AppTheme.error,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.mediumImpact();
                onAddToCart();
              },
              icon: const Icon(Icons.add_shopping_cart_rounded, size: 24),
              label: const Text('Agregar al carrito',
                  style: TextStyle(fontSize: 20)),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(64),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HEADER BADGE ICON
// ═══════════════════════════════════════════════════════════════════════════════

class _HeaderBadgeIcon extends StatelessWidget {
  final IconData icon;
  final int badgeCount;
  final Color badgeColor;
  final VoidCallback onPressed;

  const _HeaderBadgeIcon({
    required this.icon,
    required this.badgeCount,
    required this.badgeColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppTheme.textPrimary, size: 22),
            ),
            if (badgeCount > 0)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: const Color(0xFFFFFBF7), width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      height: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EMPTY INVENTORY GUIDE
// ═══════════════════════════════════════════════════════════════════════════════

class _EmptyInventoryGuide extends StatelessWidget {
  final VoidCallback onAddInventory;
  final VoidCallback onGoBack;

  const _EmptyInventoryGuide({
    required this.onAddInventory,
    required this.onGoBack,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: onGoBack,
                  icon: const Icon(Icons.arrow_back_rounded,
                      size: 28, color: AppTheme.textPrimary),
                ),
              ),
              const Spacer(),
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(36),
                ),
                child: const Icon(Icons.inventory_2_outlined,
                    size: 64, color: AppTheme.primary),
              ),
              const SizedBox(height: 28),
              const Text(
                'Su inventario está vacío',
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Para empezar a vender, primero necesita\nagregar sus productos al inventario.',
                style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey.shade600,
                    height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),
              ElevatedButton.icon(
                onPressed: onAddInventory,
                icon: const Icon(Icons.add_business_rounded, size: 26),
                label: const Text('Agregar mercancía'),
              ),
              const SizedBox(height: 14),
              Text(
                'Puede fotografiar su factura y la IA\ndetectará los productos automáticamente.',
                style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade500,
                    fontStyle: FontStyle.italic,
                    height: 1.4),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
