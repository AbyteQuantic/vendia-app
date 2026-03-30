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

/// PosScreen — Premium POS module with 10 independent carts.
/// Provides its own CartController via ChangeNotifierProvider.
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

  @override
  Widget build(BuildContext context) {
    return Consumer<CartController>(
      builder: (context, ctrl, _) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFFBF7), Color(0xFFF5F3F0)],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // ── AppBar replacement ──
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Semantics(
                          button: true,
                          label: 'Volver al inicio',
                          child: IconButton(
                            icon: const Icon(Icons.arrow_back_rounded,
                                color: AppTheme.textPrimary, size: 28),
                            tooltip: 'Volver',
                            onPressed: () => Navigator.of(context).pop(),
                          ),
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
                        PanicButton(
                          onPanicTriggered: () {
                            // TODO: send SOS via API
                          },
                        ),
                        const SizedBox(width: 6),
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
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),

                  const SyncStatusBanner(),

                  // ── Cart tabs (C1-C10) ──
                  _CartTabs(
                    activeIndex: ctrl.activeIndex,
                    onTabSelected: ctrl.switchCart,
                    cartCounts: List.generate(10, ctrl.cartCount),
                  ),

                  // ── Search bar ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F7F5),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFE8E4DF),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TextField(
                        key: const Key('search_field'),
                        controller: _searchCtrl,
                        style: const TextStyle(fontSize: 18),
                        onChanged: ctrl.setSearch,
                        decoration: InputDecoration(
                          hintText: 'Buscar producto...',
                          hintStyle: const TextStyle(
                            fontSize: 18,
                            color: Color(0xFF9CA3AF),
                          ),
                          prefixIcon: const Icon(Icons.search_rounded,
                              color: Color(0xFF9CA3AF), size: 24),
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
                          filled: true,
                          fillColor: Colors.transparent,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 18),
                        ),
                      ),
                    ),
                  ),

                  // ── Main content: grid + cart ──
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Product grid (60%)
                        Expanded(
                          flex: 6,
                          child: _ProductGrid(
                            products: ctrl.filteredProducts,
                            onAdd: (p) =>
                                _addProductWithContainerCheck(ctrl, p),
                            onLongPress: (p) =>
                                _showProductDetailModal(p, ctrl),
                          ),
                        ),

                        // Subtle separator
                        Container(
                          width: 1,
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          color: const Color(0xFFE8E4DF),
                        ),

                        // Active cart panel (40%)
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
            ),
          ),
        );
      },
    );
  }
}

// ── Cart Tabs ─────────────────────────────────────────────────────────────────

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
      height: 64,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: cartCounts.length,
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
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: isActive
                      ? const LinearGradient(
                          colors: [Color(0xFF1A2FA0), Color(0xFF2541B2)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: isActive ? null : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: hasItems
                      ? Border.all(color: const Color(0xFFF59E0B), width: 2)
                      : null,
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color:
                                const Color(0xFF1A2FA0).withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ]
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
                                : const Color(0xFFBBBBBB),
                      ),
                    ),
                    if (isActive)
                      Text(
                        'Activa',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.85),
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

// ── Product Grid ──────────────────────────────────────────────────────────────

class _ProductGrid extends StatelessWidget {
  final List<Product> products;
  final ValueChanged<Product> onAdd;
  final ValueChanged<Product> onLongPress;

  const _ProductGrid({
    required this.products,
    required this.onAdd,
    required this.onLongPress,
  });

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
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.72,
      ),
      itemCount: products.length,
      itemBuilder: (_, i) => _ProductCard(
        index: i,
        product: products[i],
        onTap: () => onAdd(products[i]),
        onLongPress: () => onLongPress(products[i]),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final int index;
  final Product product;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ProductCard({
    required this.index,
    required this.product,
    required this.onTap,
    required this.onLongPress,
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
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image or gradient placeholder
              _ProductImageSection(
                imageUrl: product.imageUrl,
                height: 90,
              ),

              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                          height: 1.2,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
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
                          // 60x60 touch target wrapping the 48x48 visual button
                          SizedBox(
                            width: 60,
                            height: 60,
                            child: Center(
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      AppTheme.primary,
                                      AppTheme.primaryLight
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primary
                                          .withValues(alpha: 0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.add,
                                    color: Colors.white, size: 24),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
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

// ── Product image section (shared between card and modal) ─────────────────────

class _ProductImageSection extends StatelessWidget {
  final String? imageUrl;
  final double height;

  const _ProductImageSection({required this.imageUrl, required this.height});

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        child: Image.network(
          imageUrl!,
          height: height,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _GradientPlaceholder(height: height),
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return _GradientPlaceholder(height: height);
          },
        ),
      );
    }
    return _GradientPlaceholder(height: height);
  }
}

class _GradientPlaceholder extends StatelessWidget {
  final double height;

  const _GradientPlaceholder({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF0F4FF), Color(0xFFE8EEFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.inventory_2_rounded,
            color: AppTheme.primary,
            size: 24,
          ),
        ),
      ),
    );
  }
}

// ── Cart Panel ────────────────────────────────────────────────────────────────

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
        // Cart header
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Text(
                'Cuenta C${activeIndex + 1}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              if (items.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onClear();
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Limpiar',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.error,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Cart list
        Expanded(
          child: items.isEmpty
              ? ListView(
                  key: const Key('cart_list'),
                  children: const [
                    Center(
                      key: Key('cart_empty_msg'),
                      child: Padding(
                        padding: EdgeInsets.only(top: 48),
                        child: Column(
                          children: [
                            Icon(
                              Icons.shopping_cart_outlined,
                              size: 48,
                              color: Color(0xFFD6D0C8),
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Carrito vacio',
                              style: TextStyle(
                                fontSize: 18,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : ListView(
                  key: const Key('cart_list'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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

        // QR + COBRAR buttons
        if (items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
            child: Row(
              children: [
                // QR button
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
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primary.withValues(alpha: 0.15),
                          AppTheme.primaryLight.withValues(alpha: 0.1),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.qr_code_2_rounded,
                      size: 28,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // COBRAR button
                Expanded(
                  child: GestureDetector(
                    key: const Key('btn_cobrar'),
                    onTap: () {
                      HapticFeedback.heavyImpact();
                      // TODO: payment flow
                    },
                    child: Container(
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0D9668), Color(0xFF10B981)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFF0D9668).withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
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
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  // Decrement button
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
                          color: const Color(0xFFF3F0EC),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(Icons.remove,
                            size: 24, color: AppTheme.textSecondary),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text(
                      '${item.quantity}',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ),
                  // Increment button
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
                          gradient: const LinearGradient(
                            colors: [AppTheme.primary, AppTheme.primaryLight],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  AppTheme.primary.withValues(alpha: 0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
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

// ── Product Detail Bottom Sheet ───────────────────────────────────────────────

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
          // Drag handle
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

          // Large image or placeholder
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: _ProductImageSection(
                imageUrl: product.imageUrl,
                height: 200,
              ),
            ),
          ),

          // Product details
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(
              product.name,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              product.formattedPrice,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppTheme.primary,
              ),
            ),
          ),

          // Stock info
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: product.stock > 0
                        ? AppTheme.success
                        : AppTheme.error,
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
                if (product.requiresContainer) ...[
                  const SizedBox(width: 16),
                  const Icon(Icons.recycling_rounded,
                      size: 20, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  const Text(
                    'Requiere envase',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Add to cart button
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                onAddToCart();
              },
              child: Container(
                height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.primary, AppTheme.primaryLight],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_shopping_cart_rounded,
                        color: Colors.white, size: 24),
                    SizedBox(width: 10),
                    Text(
                      'Agregar al carrito',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Header Badge Icon ─────────────────────────────────────────────────────────

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
          width: 40,
          height: 40,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
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
      ),
    );
  }
}
