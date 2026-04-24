import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../../models/app_notification.dart';
import '../../models/cart_item.dart';
import '../../models/product.dart';
import '../../theme/app_theme.dart';
import '../../widgets/notification_center_sheet.dart';
import '../../widgets/panic_button.dart';
import '../../widgets/table_qr_sheet.dart';
import '../../widgets/stock_badge.dart';
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
import '../../services/panic_trigger_service.dart';
import '../../database/collections/local_sale.dart';
import '../inventory/add_merchandise_screen.dart';
import '../tables/tab_review_screen.dart';

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
  // Label-indexed snapshot of tabs currently open on the server.
  // Populated by _loadOpenTabs(); the mesa selector reads it to
  // decorate occupied tables with a badge and their running total.
  // Key is the raw label string (case preserved) to keep lookup
  // simple; the mesa button already renders the same label so the
  // match is exact.
  Map<String, double> _openTabTotalsByLabel = const {};
  int _pendingFiados = 0;
  List<Map<String, dynamic>> _notifications = [];
  int _unreadNotifications = 0;
  Timer? _notificationsTimer;
  // Cached per-session. The feature flag is resolved once on mount because
  // it can only change across a login and we don't want to rebuild the POS
  // tree chasing storage reads.
  FeatureFlags _flags = const FeatureFlags();

  @override
  void initState() {
    super.initState();
    _loadTables();
    _loadOpenTabs();
    _loadPendingFiados();
    _loadNotifications();
    _loadFeatureFlags();
    // Poll every 20s while the POS is foregrounded so the bell badge
    // reacts to fiado acceptances / new online orders without the
    // cashier needing to pull-to-refresh. Also refreshes the open-
    // tabs overlay so mesas with new deudas get their badge without
    // the cashier having to re-enter the selector.
    _notificationsTimer =
        Timer.periodic(const Duration(seconds: 20), (_) {
      _loadNotifications();
      _loadPendingFiados();
      _loadOpenTabs();
    });
  }

  Future<void> _loadFeatureFlags() async {
    final flags = await AuthService().getFeatureFlags();
    if (mounted) setState(() => _flags = flags);
  }

  Future<void> _loadTables() async {
    try {
      final api = ApiService(AuthService());
      final tables = await api.fetchTables();
      if (mounted) setState(() => _tables = tables);
    } catch (_) {}
  }

  /// "$15.000"-style formatter used in the mesa selector badges.
  /// Mirrors the grouping CartController.formattedTotal applies
  /// so the selector and the cart sheet never disagree on how a
  /// number looks.
  static String _formatMoney(double amount) {
    final cents = amount.round();
    final s = cents.toString();
    final buf = StringBuffer('\$');
    final start = s.length % 3;
    if (start > 0) buf.write(s.substring(0, start));
    for (int i = start; i < s.length; i += 3) {
      if (i > 0) buf.write('.');
      buf.write(s.substring(i, i + 3));
    }
    return buf.toString();
  }

  /// Snapshot the currently-open tabs so the mesa selector can
  /// decorate occupied tables. We fold the payload into a
  /// `{label → total}` map so the render loop is O(1) per cell.
  ///
  /// Failures are silent: this is pure UI sugar, and the cashier
  /// can still pick any mesa without it — the hydration path on
  /// CartController will pull the real state when they do.
  Future<void> _loadOpenTabs() async {
    try {
      final api = ApiService(AuthService());
      final rows = await api.fetchOpenAccounts();
      final map = <String, double>{};
      for (final row in rows) {
        final label = (row['label'] as String?)?.trim() ?? '';
        if (label.isEmpty) continue;
        final total = (row['total'] as num?)?.toDouble() ?? 0;
        // If two open tickets share a label (shouldn't happen
        // post-upsert, but guard anyway) we keep the biggest —
        // better to over-alert than to hide a debt.
        if (!map.containsKey(label) || map[label]! < total) {
          map[label] = total;
        }
      }
      if (mounted) setState(() => _openTabTotalsByLabel = map);
    } catch (_) {
      // Silent: the selector falls back to plain buttons.
    }
  }

  /// Count credits awaiting customer acceptance. Surfaced as a badge on
  /// the Cuaderno icon so the cashier can spot abandoned handshakes.
  Future<void> _loadPendingFiados() async {
    try {
      final api = ApiService(AuthService());
      final res = await api.fetchCredits(status: 'pending', perPage: 200);
      final list = (res['data'] as List?) ?? const [];
      if (mounted) setState(() => _pendingFiados = list.length);
    } catch (_) {}
  }

  /// Poll the backend notifications feed. The bell badge shows unread
  /// count. When the cashier taps the bell they see the list and the
  /// whole batch is marked as read.
  Future<void> _loadNotifications() async {
    try {
      final api = ApiService(AuthService());
      final res = await api.fetchNotifications();
      final list = ((res['data'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
      final unread =
          list.where((n) => n['is_read'] != true).length;
      if (mounted) {
        setState(() {
          _notifications = list;
          _unreadNotifications = unread;
        });
      }
    } catch (_) {}
  }

  Future<void> _showNotificationsSheet() async {
    // Mark everything read as soon as the sheet opens — matches how
    // e-mail clients clear the badge. Fire-and-forget so the UI
    // reflects immediately; backend confirms eventually.
    final hadUnread = _unreadNotifications > 0;
    if (hadUnread) {
      setState(() {
        _unreadNotifications = 0;
        _notifications = _notifications
            .map((n) => {...n, 'is_read': true})
            .toList();
      });
      ApiService(AuthService()).markNotificationsRead().catchError((_) {});
    }

    // Snapshot the list at the moment the sheet opens. We freeze
    // the unread state BEFORE clearing badges so the dots still
    // appear inside the sheet on this first render — otherwise the
    // "mark all as read" above would erase the visual cue the
    // cashier expects to see on recent items.
    final snapshot = _notifications
        .map(AppNotification.fromApi)
        .whereType<AppNotification>()
        .toList()
      ..sort((a, b) {
        final ad = a.createdAt;
        final bd = b.createdAt;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1; // nulls at the bottom
        if (bd == null) return -1;
        return bd.compareTo(ad); // newest first
      });

    // If the incoming payload had `is_read: true` for the batch we
    // just cleared, restore the unread bit locally on the snapshot
    // so the sheet still communicates "these just arrived".
    final displayed = hadUnread
        ? snapshot
            .map((n) => AppNotification(
                  id: n.id,
                  kind: n.kind,
                  title: n.title,
                  body: n.body,
                  // Treat items from the last 24h as "unread" for
                  // the duration of this sheet so the blue dot is
                  // preserved after the fire-and-forget mark-read.
                  isRead: _wasAlreadyReadBefore(n),
                  createdAt: n.createdAt,
                  rawType: n.rawType,
                  orderId: n.orderId,
                  fiadoId: n.fiadoId,
                ))
            .toList()
        : snapshot;

    if (!mounted) return;
    await showNotificationCenter(context, items: displayed);
  }

  /// Best-effort check against the raw payload snapshot taken before
  /// the optimistic mark-read above. The upstream map is mutated
  /// via `setState`; we capture a local copy here keyed by id.
  bool _wasAlreadyReadBefore(AppNotification n) {
    // After setState above, every entry in _notifications has
    // is_read=true. That's fine — we only want to know "did the
    // original batch include this id as already-read?". We don't
    // persist the pre-clear snapshot to keep the refactor surgical;
    // default to false so everything rendered during this session
    // gets the blue-dot affordance at least once. Subsequent opens
    // (after the next poll cycle) will correctly show no dots.
    return false;
  }

  @override
  void dispose() {
    _notificationsTimer?.cancel();
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
    final activeCtx = ctrl.activeContext;
    // Only surface the QR affordance when the cashier is standing
    // on a table context (both "cuenta abierta" and "pago
    // inmediato" qualify — a QR is useful even for the immediate
    // variant so the diner can split the check).
    final String? activeTableLabel = (activeCtx.type == AccountType.mesa ||
            activeCtx.type == AccountType.mesaInmediata)
        ? activeCtx.tableLabel
        : null;
    final sessionToken = activeCtx.sessionToken;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AccountContextSheet(
        activeTableLabel: activeTableLabel,
        onShowTableQr: activeTableLabel == null
            ? null
            : () {
                Navigator.of(context).pop();
                // Hand the sheet the token the controller already
                // resolved so the QR paints without a round-trip
                // when the cart has been synced in the background.
                showTableQrSheet(
                  context,
                  tableLabel: activeTableLabel,
                  knownSessionToken: sessionToken,
                );
              },
        onShowTabReview:
            (activeTableLabel == null || sessionToken == null || sessionToken.isEmpty)
                ? null
                : () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => TabReviewScreen(
                        sessionToken: sessionToken,
                        tableLabel: activeTableLabel,
                        orderId: activeCtx.orderId,
                      ),
                    ));
                  },
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
                      // Mesa is "occupied" when the server is
                      // currently holding an open tab for this
                      // exact label. We surface the running total
                      // as a compact subtitle so the cashier
                      // spots a big debt before tapping.
                      final openTotal = _openTabTotalsByLabel[label];
                      final isOccupied = openTotal != null && openTotal > 0;
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          ctrl.setContext(AccountContext(
                            type: mesaType,
                            tableLabel: label,
                          ));
                          Navigator.of(context).pop();
                        },
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: isOccupied
                                    ? AppTheme.warning.withValues(alpha: 0.10)
                                    : accentColor.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isOccupied
                                      ? AppTheme.warning.withValues(alpha: 0.55)
                                      : accentColor.withValues(alpha: 0.3),
                                  width: isOccupied ? 1.8 : 1,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.table_restaurant_rounded,
                                        color: isOccupied
                                            ? AppTheme.warning
                                            : accentColor,
                                        size: 24,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: isOccupied
                                                ? AppTheme.warning
                                                : accentColor,
                                          )),
                                      if (isOccupied) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          _formatMoney(openTotal),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.warning,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // "Open" dot — a loud visual cue that
                            // scans faster than reading the total.
                            if (isOccupied)
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: AppTheme.warning,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
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
      List<CartItem> cartItems,
      String paymentMethod,
      String saleUuid, {
      String? creditAccountId,
      String? dynamicQrPayload,
      }) async {
    try {
      final api = ApiService(AuthService());
      final payload = <String, dynamic>{
        'id': saleUuid,
        'payment_method': paymentMethod,
        'items': cartItems.map((item) {
          if (item.isService) {
            return {
              'quantity': item.quantity,
              'is_service': true,
              'custom_description':
                  item.customDescription ?? item.product.name,
              'custom_unit_price':
                  item.customUnitPrice ?? item.product.price,
            };
          }
          return {
            'product_id': item.product.uuid.isNotEmpty
                ? item.product.uuid
                : item.product.id.toString(),
            'quantity': item.quantity,
          };
        }).toList(),
      };
      if (creditAccountId != null && creditAccountId.isNotEmpty) {
        payload['credit_account_id'] = creditAccountId;
      }
      if (dynamicQrPayload != null && dynamicQrPayload.isNotEmpty) {
        payload['dynamic_qr_payload'] = dynamicQrPayload;
        payload['payment_status'] = 'COMPLETED';
      }
      await api.createSale(payload);
      debugPrint('[SALE_SYNC] ok uuid=$saleUuid credit=${creditAccountId ?? "-"}');
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
      // Non-blocking: keep the UX flowing. The sale stays in Isar with
      // synced=false, and SalesSyncService.pushToServer retries on next
      // app start + every background tick. Show a subtle banner so the
      // cashier knows to reopen the app when online.
      debugPrint('[SALE_SYNC] failed uuid=$saleUuid: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.warning,
          content: Text(
            'Venta guardada localmente — no se pudo enviar al servidor: '
            '${e.toString().length > 80 ? '${e.toString().substring(0, 80)}…' : e}',
            style: const TextStyle(fontSize: 14),
          ),
        ));
      }
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
          ..creditAccountId = result.creditAccountId
          ..items = saleItems
          ..createdAt = DateTime.now()
          ..synced = false;

        await db.insertSaleAndDeductStock(localSale);

        // Copy cart items BEFORE clearing (List is reference type)
        final cartSnapshot = List<CartItem>.from(ctrl.activeCart);

        ctrl.clearActiveCart();

        // Sync sale to backend (fire and forget — don't block UX). When
        // the cashier appended to an existing fiado the checkout result
        // carries the credit_account_id so the backend can link the sale
        // to the debt for itemized display on the customer statement.
        _syncSaleToBackend(
          cartSnapshot,
          result.paymentMethod,
          saleUuid,
          creditAccountId: result.creditAccountId,
          dynamicQrPayload: result.dynamicQrPayload,
        );
        // Credit sales can leave a fiado in pending state; refresh the
        // badge so the cashier sees it in the Cuaderno indicator.
        if (result.paymentMethod == 'credit') _loadPendingFiados();

        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SaleSuccessScreen(
              total: saleTotalFormatted,
              paymentMethod: result.paymentMethod,
              fiadoPending: result.fiadoPending,
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

  /// Show the ad-hoc service charge modal. Only called when the
  /// `enable_services` feature flag is true (reparacion_muebles,
  /// manufactura, emprendimiento_general). The returned tuple is pushed
  /// into the cart as a non-inventory line.
  Future<void> _showServiceChargeSheet(CartController ctrl) async {
    HapticFeedback.lightImpact();
    final result = await showModalBottomSheet<_ServiceChargeResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: const _ServiceChargeSheet(),
      ),
    );
    if (result == null || !mounted) return;
    ctrl.addServiceCharge(
      description: result.description,
      unitPrice: result.unitPrice,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text('🛠️ ${result.description} agregado al carrito'),
      ),
    );
  }

  void _sendOrder(CartController ctrl) {
    final ctx = ctrl.activeContext;
    // Persist FIRST so the live-tab QR has a session_token by the
    // time the cashier opens the account sheet. We fire-and-forget
    // because the debounced syncs along the way have almost
    // certainly already landed; this flush is a safety net. The
    // UI keeps the mesa assigned and only clears line items.
    unawaited(ctrl.flushTableTab());
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
                      PanicButton(onPanicTriggered: PanicTriggerService.trigger),
                      const SizedBox(width: 6),
                      _HeaderBadgeIcon(
                        icon: Icons.menu_book_rounded,
                        badgeCount: _pendingFiados,
                        badgeColor: const Color(0xFF6D28D9),
                        onPressed: () async {
                          HapticFeedback.lightImpact();
                          final result = await Navigator.of(context).push<Map<String, String>>(
                            MaterialPageRoute(
                              builder: (_) => const CuadernoFiadosScreen(),
                            ),
                          );
                          // Refresh pending count whenever we come back.
                          _loadPendingFiados();
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
                        badgeCount: _unreadNotifications,
                        badgeColor: const Color(0xFFFF6B6B),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          _showNotificationsSheet();
                        },
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

                // ── Cobrar Servicio (feature flag: enable_services) ──
                if (_flags.enableServices)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: ServiceChargeButton(
                      onPressed: () => _showServiceChargeSheet(ctrl),
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
      // Absolute card height via mainAxisExtent — prevents overflow on any
      // screen width. maxCrossAxisExtent caps card width so phones get 2
      // columns (~180 each) and tablets get 3+ without deforming the card.
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: 260,
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
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: StockBadge(stock: product.stock),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        // Price + qty controls row. FittedBox guarantees the
                        // whole row scales down on narrow devices so the
                        // trash / minus / qty / plus never overflow the card.
                        SizedBox(
                          height: 32,
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  product.formattedPrice,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
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

              // Hydration banner — shown when we're pulling the
              // server-side open tab for a just-selected mesa.
              // Non-blocking: the cart below still renders the
              // previous snapshot so the cashier can keep typing.
              if (ctrl.isHydratingTab(ctrl.activeIndex))
                Container(
                  key: const Key('pos_cart_hydration_banner'),
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.25)),
                  ),
                  child: const Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppTheme.primary,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Cargando cuenta abierta de la mesa…',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
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

  /// Label of the currently active table ("Mesa 1", …). When set,
  /// we surface an additional "Mostrar QR de la cuenta" affordance
  /// at the top of the sheet. Null for mostrador / fiado contexts.
  final String? activeTableLabel;
  final VoidCallback? onShowTableQr;
  /// Tab review — a read of the cuenta detallada (items + horas +
  /// abonos + saldo) so the tendero doesn't have to re-sum the
  /// ticket mentally when a customer asks "¿cuánto voy?".
  final VoidCallback? onShowTabReview;

  const _AccountContextSheet({
    required this.onMostrador,
    required this.onMesa,
    required this.onFiado,
    required this.onMesaInmediata,
    this.activeTableLabel,
    this.onShowTableQr,
    this.onShowTabReview,
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

            if (activeTableLabel != null && onShowTabReview != null) ...[
              // Tab review (priority option per the live-tab epic) —
              // detailed cuenta read so the tendero never has to
              // sum items in their head when a diner asks for the
              // total halfway through the meal.
              _ContextOption(
                key: const Key('context_show_tab_review'),
                icon: Icons.receipt_long_rounded,
                emoji: '🧾',
                label: 'Ver Detalle de la Cuenta',
                subtitle: 'Items con hora, abonos y saldo de ${activeTableLabel!}',
                color: const Color(0xFFEA580C),
                onTap: onShowTabReview!,
              ),
              const SizedBox(height: 12),
            ],

            if (activeTableLabel != null && onShowTableQr != null) ...[
              // Live-tab QR — shown only when a table is already
              // active in the current cart. Tapping delegates to
              // the parent which closes THIS sheet before opening
              // the QR sheet, keeping the nav stack shallow.
              _ContextOption(
                key: const Key('context_show_table_qr'),
                icon: Icons.qr_code_2_rounded,
                emoji: '📱',
                label: 'Mostrar QR de la cuenta',
                subtitle: 'El cliente ve ${activeTableLabel!} en vivo',
                color: AppTheme.primary,
                onTap: onShowTableQr!,
              ),
              const SizedBox(height: 12),
            ],

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
    super.key,
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
                  ? Image.network(
                      product.imageUrl!,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Container(
                        height: 200,
                        color: const Color(0xFFF0F4FF),
                        child: const Center(
                          child: Icon(Icons.inventory_2_rounded,
                              color: AppTheme.primary, size: 48),
                        ),
                      ),
                    )
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

// ── Service Charge (feature flag: enable_services) ───────────────────────────

/// Result of the service-charge bottom sheet. Simple record-like class
/// to avoid dragging in a full-blown domain model for a modal output.
class _ServiceChargeResult {
  final String description;
  final double unitPrice;
  const _ServiceChargeResult(this.description, this.unitPrice);
}

/// Accent-colored tile rendered above the product grid for service-first
/// businesses (repair shops, manufacturing, emprendimientos). Deliberately
/// uses a different color than primary so the cashier can spot it at a
/// glance amid the product-heavy POS.
class ServiceChargeButton extends StatelessWidget {
  final VoidCallback onPressed;
  const ServiceChargeButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        key: const Key('btn_cobrar_servicio'),
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF7C3AED),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        icon: const Icon(Icons.build_rounded, size: 22),
        label: const Text(
          '🛠️ Cobrar Servicio / Ítem Personalizado',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// Stateful bottom sheet that collects a description + price for an
/// ad-hoc charge. Validation mirrors the backend's validateSaleItemRequest
/// (non-empty description, price > 0) so the sheet never produces a
/// payload that would 400 from the API.
class _ServiceChargeSheet extends StatefulWidget {
  const _ServiceChargeSheet();

  @override
  State<_ServiceChargeSheet> createState() => _ServiceChargeSheetState();
}

class _ServiceChargeSheetState extends State<_ServiceChargeSheet> {
  final _formKey = GlobalKey<FormState>();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  @override
  void dispose() {
    _descCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final price = double.tryParse(_priceCtrl.text.replaceAll(',', '.')) ?? 0;
    Navigator.of(context).pop(
      _ServiceChargeResult(_descCtrl.text.trim(), price),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFD6D0C8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Cobrar servicio o ítem personalizado',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'No descuenta inventario. Se agrega directamente al carrito.',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            TextFormField(
              key: const Key('svc_desc_input'),
              controller: _descCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Descripción',
                hintText: 'Ej: Reparación de mesa de centro',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Descripción requerida';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('svc_price_input'),
              controller: _priceCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Valor a cobrar',
                prefixText: r'$ ',
                hintText: '50000',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final parsed =
                    double.tryParse((v ?? '').replaceAll(',', '.'));
                if (parsed == null || parsed <= 0) {
                  return 'Ingrese un valor mayor a 0';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              key: const Key('svc_submit'),
              onPressed: _submit,
              icon: const Icon(Icons.add_shopping_cart_rounded),
              label: const Text('Agregar al carrito'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

