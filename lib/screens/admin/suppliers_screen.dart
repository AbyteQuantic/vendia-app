import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';

class _Supplier {
  final String name;
  final String contact;
  final String phone;
  final String emoji;
  final List<Color> avatarGradient;

  const _Supplier({
    required this.name,
    required this.contact,
    required this.phone,
    required this.emoji,
    required this.avatarGradient,
  });
}

class SuppliersScreen extends StatelessWidget {
  const SuppliersScreen({super.key});

  static const List<_Supplier> _suppliers = [
    _Supplier(
      name: 'Bavaria',
      contact: 'Carlos Mendez',
      phone: '310 555 1234',
      emoji: '\uD83C\uDF7A',
      avatarGradient: [Color(0xFFF59E0B), Color(0xFFD97706)],
    ),
    _Supplier(
      name: 'Postobon',
      contact: 'Maria Garcia',
      phone: '311 444 5678',
      emoji: '\uD83E\uDD64',
      avatarGradient: [Color(0xFFEF4444), Color(0xFFDC2626)],
    ),
    _Supplier(
      name: 'Bimbo Colombia',
      contact: 'Jorge Ramirez',
      phone: '315 333 9012',
      emoji: '\uD83C\uDF5E',
      avatarGradient: [Color(0xFF3B82F6), Color(0xFF2563EB)],
    ),
    _Supplier(
      name: 'Alpina',
      contact: 'Ana Rodriguez',
      phone: '320 222 3456',
      emoji: '\uD83E\uDD5B',
      avatarGradient: [Color(0xFF10B981), Color(0xFF059669)],
    ),
    _Supplier(
      name: 'Frito Lay',
      contact: 'Pedro Hernandez',
      phone: '318 111 7890',
      emoji: '\uD83C\uDF5F',
      avatarGradient: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: Semantics(
          button: true,
          label: 'Volver',
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppTheme.textPrimary, size: 28),
            tooltip: 'Volver',
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop();
            },
          ),
        ),
        title: const Text(
          'Mis Proveedores',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Header ─────────────────────────────────────────────────
          Container(
            width: double.infinity,
            height: 120,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF764BA2), Color(0xFF667EEA)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Mis Proveedores',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_suppliers.length} proveedores registrados',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Supplier List ──────────────────────────────────────────
          Expanded(
            child: ListView.separated(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              itemCount: _suppliers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final s = _suppliers[index];
                return _SupplierCard(supplier: s);
              },
            ),
          ),
        ],
      ),
      floatingActionButton: Semantics(
        button: true,
        label: 'Nuevo Proveedor',
        child: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            // TODO: navigate to add supplier form
          },
          child: Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF764BA2), Color(0xFF667EEA)],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF764BA2).withValues(alpha: 0.4),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, color: Colors.white, size: 26),
                SizedBox(width: 8),
                Text(
                  'Nuevo Proveedor',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Supplier Card ────────────────────────────────────────────────────────────

class _SupplierCard extends StatelessWidget {
  final _Supplier supplier;

  const _SupplierCard({required this.supplier});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: supplier.avatarGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Text(
              supplier.emoji,
              style: const TextStyle(fontSize: 26),
            ),
          ),
          const SizedBox(width: 14),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  supplier.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${supplier.contact} \u2014 ${supplier.phone}',
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // WhatsApp button
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              // TODO: launch WhatsApp with supplier phone
            },
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFF25D366),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.chat_rounded,
                  color: Colors.white, size: 26),
            ),
          ),
        ],
      ),
    );
  }
}
