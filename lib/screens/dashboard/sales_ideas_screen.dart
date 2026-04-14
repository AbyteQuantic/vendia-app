import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../database/database_service.dart';
import '../../theme/app_theme.dart';

/// AI-powered sales improvement suggestions — Gerontodiseño.
class SalesIdeasScreen extends StatefulWidget {
  const SalesIdeasScreen({super.key});

  @override
  State<SalesIdeasScreen> createState() => _SalesIdeasScreenState();
}

class _SalesIdeasScreenState extends State<SalesIdeasScreen> {
  final _db = DatabaseService.instance;
  List<_Idea> _ideas = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  Future<void> _analyze() async {
    final sales = await _db.getSalesToday();
    final products = await _db.getAllProducts();

    final ideas = <_Idea>[];

    // ── Payment diversity ──────────────────────────────────────────────
    final cashOnly = sales.every((s) => s.paymentMethod == 'cash');
    if (sales.isNotEmpty && cashOnly) {
      ideas.add(_Idea(
        icon: Icons.phone_android_rounded,
        color: const Color(0xFF3B82F6),
        title: 'Active pagos digitales',
        body: 'Todas las ventas son en efectivo. Active Nequi o Daviplata '
            'en Mi Negocio > Metodos de Pago para captar clientes que no cargan billetes.',
      ));
    }

    // ── Low transaction count ──────────────────────────────────────────
    if (sales.length < 5) {
      ideas.add(_Idea(
        icon: Icons.local_offer_rounded,
        color: const Color(0xFFEA580C),
        title: 'Promocion 2x1 o combo',
        body: 'Pocas ventas hoy. Considere armar un combo con productos de baja '
            'rotacion. Ejemplo: "Lleve 2 gaseosas por el precio de 1.5".',
      ));
    }

    // ── Credit exposure ────────────────────────────────────────────────
    final creditSales = sales.where((s) => s.paymentMethod == 'credit');
    if (creditSales.isNotEmpty) {
      final creditTotal = creditSales.fold<double>(0, (s, e) => s + e.total);
      final total = sales.fold<double>(0, (s, e) => s + e.total);
      if (total > 0 && creditTotal / total > 0.3) {
        ideas.add(_Idea(
          icon: Icons.warning_amber_rounded,
          color: const Color(0xFFDC2626),
          title: 'Muchos fiados hoy',
          body: 'El ${(creditTotal / total * 100).round()}% de las ventas son a credito. '
              'Envie recordatorios por WhatsApp desde el modulo de Fiados.',
        ));
      }
    }

    // ── Stock alerts ───────────────────────────────────────────────────
    final lowStock = products.where((p) => p.stock > 0 && p.stock <= 3);
    if (lowStock.isNotEmpty) {
      ideas.add(_Idea(
        icon: Icons.inventory_2_rounded,
        color: const Color(0xFF7C3AED),
        title: 'Productos por agotarse',
        body: '${lowStock.length} producto${lowStock.length > 1 ? 's' : ''} '
            'tiene${lowStock.length > 1 ? 'n' : ''} 3 unidades o menos. '
            'Reabastezca: ${lowStock.take(3).map((p) => p.name).join(", ")}.',
      ));
    }

    // ── Products without photo ─────────────────────────────────────────
    final noPhoto = products.where(
        (p) => p.isAvailable && (p.imageUrl == null || p.imageUrl!.isEmpty));
    if (noPhoto.length > 3) {
      ideas.add(_Idea(
        icon: Icons.photo_camera_rounded,
        color: const Color(0xFF10B981),
        title: 'Agregue fotos a sus productos',
        body: '${noPhoto.length} productos no tienen foto. Los productos con imagen '
            'se venden hasta 30% mas rapido.',
      ));
    }

    // ── Default tip ────────────────────────────────────────────────────
    if (ideas.isEmpty) {
      ideas.add(_Idea(
        icon: Icons.check_circle_rounded,
        color: AppTheme.success,
        title: 'Todo va bien',
        body: 'No hay alertas por ahora. Siga registrando sus ventas para '
            'recibir sugerencias personalizadas.',
      ));
    }

    if (mounted) setState(() { _ideas = ideas; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFBF7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: Color(0xFF7C3AED), size: 24),
            SizedBox(width: 10),
            Text('Ideas para Vender Mas',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF7C3AED)))
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: _ideas.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (_, i) {
                final idea = _ideas[i];
                return Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: idea.color.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                        color: idea.color.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          color: idea.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(idea.icon, color: idea.color, size: 26),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(idea.title,
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w700,
                                    color: idea.color)),
                            const SizedBox(height: 6),
                            Text(idea.body,
                                style: const TextStyle(
                                    fontSize: 16, color: Colors.black87,
                                    height: 1.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _Idea {
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  const _Idea({
    required this.icon, required this.color,
    required this.title, required this.body,
  });
}
