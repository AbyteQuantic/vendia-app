import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/cart_item.dart';
import '../../models/product.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panic_button.dart';
import '../../widgets/sync_status_banner.dart';
import 'cart_controller.dart';
import 'account_qr_screen.dart';
import 'widgets/container_dialog.dart';

/// PosScreen — Módulo de venta con 5 carritos independientes.
/// Consume CartController vía Provider.
class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _searchCtrl = TextEditingController();

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

  @override
  Widget build(BuildContext context) {
    return Consumer<CartController>(
      builder: (context, ctrl, _) {
        return Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            backgroundColor: AppTheme.background,
            elevation: 0,
            leading: Semantics(
              button: true,
              label: 'Volver al inicio',
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded,
                    color: AppTheme.textPrimary, size: 28),
                tooltip: 'Volver',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            title: const Text(
              'Vender',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            actions: [
              // Botón de pánico silencioso
              PanicButton(
                onPanicTriggered: () {
                  // TODO: send SOS via API
                },
              ),
              const SizedBox(width: 6),
              // Rockola / Música
              _HeaderBadgeIcon(
                key: const Key('btn_music'),
                icon: Icons.music_note_rounded,
                badgeCount: 3,
                badgeColor: const Color(0xFF764BA2),
                tooltip: 'Rockola',
                onPressed: () {
                  HapticFeedback.lightImpact();
                  // TODO: navigate to rockola
                },
              ),
              const SizedBox(width: 6),
              // Notificaciones KDS
              _HeaderBadgeIcon(
                key: const Key('btn_notifications'),
                icon: Icons.notifications_rounded,
                badgeCount: 2,
                badgeColor: const Color(0xFFFF6B6B),
                tooltip: 'Notificaciones',
                onPressed: () {
                  HapticFeedback.lightImpact();
                  // TODO: navigate to KDS notifications
                },
              ),
              const SizedBox(width: 12),
            ],
          ),
          body: Column(
            children: [
              const SyncStatusBanner(),

              // ── Pestañas de carrito (1–5) ──────────────────────────────────
              _CartTabs(
                activeIndex: ctrl.activeIndex,
                onTabSelected: ctrl.switchCart,
                cartCounts: List.generate(10, ctrl.cartCount),
              ),

              // ── Buscador ───────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: TextField(
                  key: const Key('search_field'),
                  controller: _searchCtrl,
                  style: const TextStyle(fontSize: 18),
                  onChanged: ctrl.setSearch,
                  decoration: InputDecoration(
                    hintText: 'Buscar producto...',
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: AppTheme.primary, size: 24),
                    suffixIcon: ValueListenableBuilder(
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
                  ),
                ),
              ),

              // ── Contenido principal: grid + carrito ────────────────────────
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Grid de productos (60% del ancho)
                    Expanded(
                      flex: 6,
                      child: _ProductGrid(
                        products: ctrl.filteredProducts,
                        onAdd: (p) => _addProductWithContainerCheck(ctrl, p),
                      ),
                    ),

                    const VerticalDivider(width: 1, thickness: 1),

                    // Panel de carrito activo (40% del ancho)
                    Expanded(
                      flex: 4,
                      child: _CartPanel(
                        items: ctrl.activeCart,
                        total: ctrl.formattedTotal,
                        activeIndex: ctrl.activeIndex,
                        onIncrement: ctrl.increment,
                        onDecrement: ctrl.decrement,
                        onClear: ctrl.clearActiveCart,
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
}

// ── Pestañas de carrito ────────────────────────────────────────────────────────

class _CartTabs extends StatelessWidget {
  final int activeIndex;
  final ValueChanged<int> onTabSelected;
  final List<int> cartCounts;

  const _CartTabs({
    required this.activeIndex,
    required this.onTabSelected,
    required this.cartCounts,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      color: AppTheme.surfaceGrey,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: cartCounts.length, // 10 cuentas
        itemBuilder: (_, i) {
          final isActive = activeIndex == i;
          final count = cartCounts[i];
          final hasItems = count > 0 && !isActive;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: GestureDetector(
              key: Key('cart_tab_${i + 1}'),
              onTap: () {
                HapticFeedback.lightImpact();
                onTabSelected(i);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 55,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: isActive
                      ? const LinearGradient(
                          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: isActive ? null : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: hasItems
                      ? Border.all(color: const Color(0xFFF59E0B), width: 2)
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'C${i + 1}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: isActive
                            ? Colors.white
                            : hasItems
                                ? AppTheme.textPrimary
                                : const Color(0xFF9CA3AF),
                      ),
                    ),
                    if (isActive)
                      Text(
                        'Activa',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    if (hasItems)
                      Text(
                        '$count',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Grid de productos ──────────────────────────────────────────────────────────

class _ProductGrid extends StatelessWidget {
  final List<Product> products;
  final ValueChanged<Product> onAdd;

  const _ProductGrid({required this.products, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const Center(
        key: Key('product_grid_empty'),
        child: Text(
          'Sin resultados',
          style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
        ),
      );
    }

    return GridView.builder(
      key: const Key('product_grid'),
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.80,
      ),
      itemCount: products.length,
      itemBuilder: (_, i) => _ProductCard(
        index: i,
        product: products[i],
        onTap: () => onAdd(products[i]),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final int index;
  final Product product;
  final VoidCallback onTap;

  const _ProductCard({
    required this.index,
    required this.product,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label:
          'Agregar ${product.name} al carrito. Precio: ${product.formattedPrice}',
      child: GestureDetector(
        key: Key('product_card_$index'),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceGrey,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.borderColor, width: 1.5),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.inventory_2_rounded,
                    color: AppTheme.primary, size: 24),
              ),
              const Spacer(),
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      product.formattedPrice,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 24),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Panel del carrito activo ───────────────────────────────────────────────────

class _CartPanel extends StatelessWidget {
  final List<CartItem> items;
  final String total;
  final int activeIndex;
  final ValueChanged<Product> onIncrement;
  final ValueChanged<Product> onDecrement;
  final VoidCallback onClear;

  const _CartPanel({
    required this.items,
    required this.total,
    required this.activeIndex,
    required this.onIncrement,
    required this.onDecrement,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Lista del carrito — siempre visible con key cart_list
        Expanded(
          child: items.isEmpty
              ? ListView(
                  key: const Key('cart_list'),
                  children: const [
                    Center(
                      key: Key('cart_empty_msg'),
                      child: Padding(
                        padding: EdgeInsets.only(top: 32),
                        child: Text(
                          'Carrito vacío',
                          style: TextStyle(
                              fontSize: 18, color: AppTheme.textSecondary),
                        ),
                      ),
                    ),
                  ],
                )
              : ListView(
                  key: const Key('cart_list'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  children: [
                    for (int i = 0; i < items.length; i++)
                      _CartItemRow(
                        index: i,
                        item: items[i],
                        onIncrement: () => onIncrement(items[i].product),
                        onDecrement: () => onDecrement(items[i].product),
                      ),
                  ],
                ),
        ),

        // Botones QR + COBRAR
        if (items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                // Botón QR de cuenta
                GestureDetector(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AccountQrScreen(
                          accountLabel: 'C${activeIndex + 1}',
                          cartLabel: 'Cuenta Activa',
                          accountUuid: 'cuenta-$activeIndex',
                        ),
                      ),
                    );
                  },
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: const Color(0xFF667EEA).withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.qr_code_2_rounded,
                      size: 28,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Botón COBRAR
                Expanded(
                  child: ElevatedButton(
                    key: const Key('btn_cobrar'),
                    onPressed: () {
                      // TODO: flujo de pago
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      minimumSize: const Size(double.infinity, 60),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                    child: Text(
                      'COBRAR $total',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CartItemRow extends StatelessWidget {
  final int index;
  final CartItem item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  const _CartItemRow({
    required this.index,
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('cart_item_$index'),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceGrey,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.product.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Semantics(
                    button: true,
                    label: 'Disminuir cantidad de ${item.product.name}',
                    child: GestureDetector(
                      key: Key('cart_item_dec_$index'),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        onDecrement();
                      },
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: AppTheme.borderColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.remove, size: 24),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      '${item.quantity}',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Aumentar cantidad de ${item.product.name}',
                    child: GestureDetector(
                      key: Key('cart_item_inc_$index'),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        onIncrement();
                      },
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.add,
                            size: 24, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                item.formattedSubtotal,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Icono de header con badge ─────────────────────────────────────────────────

class _HeaderBadgeIcon extends StatelessWidget {
  final IconData icon;
  final int badgeCount;
  final Color badgeColor;
  final String tooltip;
  final VoidCallback onPressed;

  const _HeaderBadgeIcon({
    super.key,
    required this.icon,
    required this.badgeCount,
    required this.badgeColor,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$tooltip: $badgeCount pendientes',
      child: GestureDetector(
        onTap: onPressed,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceGrey,
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
                      border: Border.all(color: AppTheme.background, width: 1.5),
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
      ),
    );
  }
}
