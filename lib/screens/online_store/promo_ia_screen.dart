import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';

/// AI-powered promotion suggestions based on inventory and sales data.
class PromoIaScreen extends StatefulWidget {
  const PromoIaScreen({super.key});

  @override
  State<PromoIaScreen> createState() => _PromoIaScreenState();
}

class _AISuggestion {
  final String emoji;
  final String productName;
  final String alertText;
  final Color alertColor;
  final String suggestionText;
  bool applied = false;

  _AISuggestion({
    required this.emoji,
    required this.productName,
    required this.alertText,
    required this.alertColor,
    required this.suggestionText,
  });
}

class _PromoIaScreenState extends State<PromoIaScreen> {
  late final List<_AISuggestion> _suggestions;

  @override
  void initState() {
    super.initState();
    _suggestions = [
      _AISuggestion(
        emoji: '\u{1F95A}',
        productName: 'Huevos (bandeja x30)',
        alertText: '\u23F3 Vence en 3 dias',
        alertColor: AppTheme.error,
        suggestionText:
            'Gana \$300/ud al vender 2\u00d71. Mejor que perder \$4.500 si se vencen.',
      ),
      _AISuggestion(
        emoji: '\u{1F35E}',
        productName: 'Pan Tajado Bimbo',
        alertText: '\u23F3 Vence en 2 dias',
        alertColor: AppTheme.error,
        suggestionText:
            'Venda con 30% descuento. Recupera \$2.100 en vez de perder \$3.000.',
      ),
      _AISuggestion(
        emoji: '\u{1F964}',
        productName: 'Jugo Hit 1L',
        alertText: '\u{1F4C9} Baja rotacion (15 dias sin vender)',
        alertColor: AppTheme.warning,
        suggestionText:
            'Ofrezca 2\u00d7\$5.000 (ahorra \$1.000 al cliente). Libere espacio en nevera.',
      ),
      _AISuggestion(
        emoji: '\u{1F9C0}',
        productName: 'Queso Mozarella 500g',
        alertText: '\u23F3 Vence en 5 dias',
        alertColor: AppTheme.warning,
        suggestionText:
            'Cree combo "Pizza Casera" con masa + queso. Margen de \$2.000 por combo.',
      ),
    ];
  }

  void _applySuggestion(int index) {
    HapticFeedback.mediumImpact();
    setState(() => _suggestions[index].applied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Promocion aplicada al POS: ${_suggestions[index].productName}',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _ignoreSuggestion(int index) {
    HapticFeedback.lightImpact();
    setState(() => _suggestions.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary, size: 28),
          tooltip: 'Volver',
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop();
          },
        ),
        title: const Text(
          'Sugerencias de la IA',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Banner ---
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF667EEA).withValues(alpha: 0.2),
                  ),
                ),
                child: const Row(
                  children: [
                    Text('\u{1F916}', style: TextStyle(fontSize: 28)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Basado en su inventario y ventas',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF667EEA),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // --- Suggestion cards ---
              ...List.generate(_suggestions.length, (index) {
                final s = _suggestions[index];
                return _buildSuggestionCard(s, index);
              }),

              if (_suggestions.isEmpty) ...[
                const SizedBox(height: 40),
                Center(
                  child: Column(
                    children: [
                      Icon(Icons.auto_awesome_rounded,
                          size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text(
                        'No hay sugerencias por ahora',
                        style: TextStyle(
                          fontSize: 20,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionCard(_AISuggestion s, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product row
          Row(
            children: [
              Text(s.emoji, style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  s.productName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Alert
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: s.alertColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              s.alertText,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: s.alertColor,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Suggestion text
          Text(
            s.suggestionText,
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 16),

          // Action buttons
          if (!s.applied)
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => _applySuggestion(index),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.success,
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Aplicar al POS',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => _ignoreSuggestion(index),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey.shade600,
                        minimumSize: const Size(0, 48),
                        side: BorderSide(color: Colors.grey.shade300, width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Ignorar',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: AppTheme.success, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Aplicada al POS',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.success,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
