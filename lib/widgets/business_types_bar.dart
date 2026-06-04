// Barra horizontal de tipos de negocio habilitados, justo debajo del
// header del Dashboard. Cada tipo se muestra como chip (ícono + texto);
// el último elemento es el botón "+" para agregar. Mantener presionado
// un chip por 2 segundos lo elimina (con confirmación del padre).
//
// El borrado y el alta los resuelve el Dashboard (persisten contra el
// backend); este widget solo dispara los callbacks y da el feedback
// visual del hold.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/business_types.dart';
import '../theme/app_theme.dart';

class BusinessTypesBar extends StatelessWidget {
  /// Tipos habilitados (valores backend, ej. 'tienda_barrio').
  final List<String> types;

  /// Abre el editor para agregar/cambiar tipos.
  final VoidCallback onAdd;

  /// Elimina un tipo (mantener presionado 2s). El padre persiste el cambio.
  final ValueChanged<String> onDelete;

  const BusinessTypesBar({
    super.key,
    required this.types,
    required this.onAdd,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (types.isEmpty) {
      // Sin tipos aún: solo el botón para agregar el primero.
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: _AddChip(onTap: onAdd),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(
        height: 46,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: types.length + 1, // +1 = botón agregar
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            if (i == types.length) return _AddChip(onTap: onAdd);
            final value = types[i];
            return _TypeChip(
              meta: businessTypeMeta(value),
              onHoldComplete: () => onDelete(value),
            );
          },
        ),
      ),
    );
  }
}

/// Chip de un tipo de negocio. Mantener presionado 2s → onHoldComplete.
/// Un toque corto muestra una pista de cómo eliminar.
class _TypeChip extends StatefulWidget {
  final BusinessTypeMeta meta;
  final VoidCallback onHoldComplete;

  const _TypeChip({required this.meta, required this.onHoldComplete});

  @override
  State<_TypeChip> createState() => _TypeChipState();
}

class _TypeChipState extends State<_TypeChip> {
  static const _holdDuration = Duration(seconds: 2);
  Timer? _timer;
  bool _holding = false;
  bool _fired = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startHold() {
    _fired = false;
    HapticFeedback.selectionClick();
    setState(() => _holding = true);
    _timer = Timer(_holdDuration, () {
      if (!mounted) return;
      _fired = true;
      setState(() => _holding = false);
      HapticFeedback.heavyImpact();
      widget.onHoldComplete();
    });
  }

  void _endHold() {
    final stillCounting = _timer?.isActive ?? false;
    _timer?.cancel();
    if (mounted) setState(() => _holding = false);
    // Soltó antes de los 2s y el hold no había disparado → fue un toque
    // corto: pista de cómo eliminar (descubribilidad para 50+).
    if (stillCounting && !_fired) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Mantenga presionado "${widget.meta.label}" 2 segundos para '
            'quitarlo',
            style: const TextStyle(fontSize: 15),
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.meta;
    return GestureDetector(
      onTapDown: (_) => _startHold(),
      onTapUp: (_) => _endHold(),
      onTapCancel: _endHold,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: Stack(
          children: [
            // Relleno rojo que crece durante el hold (feedback de 2s).
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: _holding ? 1.0 : 0.0),
                duration: _holding
                    ? _holdDuration
                    : const Duration(milliseconds: 180),
                curve: Curves.linear,
                builder: (_, t, __) => Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: t.clamp(0.0, 1.0),
                    child: Container(
                      color: AppTheme.error.withValues(alpha: 0.22),
                    ),
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: _holding
                    ? Colors.transparent
                    : AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(23),
                border: Border.all(
                  color: _holding
                      ? AppTheme.error.withValues(alpha: 0.7)
                      : AppTheme.primary.withValues(alpha: 0.22),
                  width: _holding ? 1.6 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(m.icon,
                      size: 18,
                      color: _holding ? AppTheme.error : AppTheme.primary),
                  const SizedBox(width: 7),
                  Text(
                    m.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _holding ? AppTheme.error : AppTheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Botón "+" al final de la barra — abre el editor de tipos.
class _AddChip extends StatelessWidget {
  final VoidCallback onTap;

  const _AddChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(23),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        // El Stack le da al Container restricciones SUELTAS, igual que en
        // _TypeChip: así el chip se ajusta a su contenido (~39px) en vez
        // de estirarse al alto del slot del ListView (46px) — esa era la
        // razón de que el botón "Agregar" se viera más alto que los demás.
        child: Stack(
          children: [
            Container(
              // Mismas métricas de caja que _TypeChip en reposo.
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(23),
                border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 18, color: AppTheme.primary),
                  SizedBox(width: 5),
                  Text(
                    'Agregar',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
