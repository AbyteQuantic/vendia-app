// Spec: specs/107-dashboard-v2-resumen/spec.md (FR-03/04)
//
// Carrusel táctil de círculos del héroe: cinta horizontal con snap; Vender
// primero, Catálogo online segundo y el resto según las capacidades activas
// del tenant (catálogo F041). Auto-avanza un puesto cada 10 s en bucle; el
// gesto del usuario pausa ~15 s y luego retoma desde donde quedó. Con
// "reducir movimiento" avanza sin animación. Con < 5 opciones no rota.
import 'dart:async';

import 'package:flutter/material.dart';

class HeroCarouselItem {
  const HeroCarouselItem({
    required this.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String key;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

class HeroCarousel extends StatefulWidget {
  const HeroCarousel({
    super.key,
    required this.items,
    this.autoAdvance = const Duration(seconds: 10),
    this.gesturePause = const Duration(seconds: 15),
  });

  final List<HeroCarouselItem> items;
  final Duration autoAdvance;
  final Duration gesturePause;

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  final _scroll = ScrollController();
  Timer? _timer;
  DateTime _pausedUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// Cinta duplicada para el bucle continuo (reset invisible al pasar la
  /// primera copia). Con pocas opciones no duplica ni rota (FR-03 borde).
  bool get _rotates => widget.items.length >= 5;

  List<HeroCarouselItem> get _track =>
      _rotates ? [...widget.items, ...widget.items] : widget.items;

  @override
  void initState() {
    super.initState();
    if (_rotates) {
      _timer = Timer.periodic(widget.autoAdvance, (_) => _advance());
    }
  }

  void _advance() {
    if (!mounted || !_scroll.hasClients) return;
    if (DateTime.now().isBefore(_pausedUntil)) return; // el gesto manda
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final step = _itemWidth();
    if (step <= 0) return;
    final half = step * widget.items.length;
    var next = (_scroll.offset / step).round() + 1;
    if (next * step >= half) {
      _scroll.jumpTo((next - widget.items.length - 1).clamp(0, 1000) * step);
      next = (_scroll.offset / step).round() + 1;
    }
    final target = (step * next).clamp(0.0, _scroll.position.maxScrollExtent);
    if (reduce) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(target,
          duration: const Duration(milliseconds: 450), curve: Curves.easeOut);
    }
  }

  double _itemWidth() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return 0;
    return box.size.width / 4 + 0; // 4 visibles; gap incluido en el ancho
  }

  void _onGesture() {
    _pausedUntil = DateTime.now().add(widget.gesturePause);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is ScrollStartNotification && n.dragDetails != null) {
            _onGesture();
          }
          return false;
        },
        child: LayoutBuilder(builder: (context, constraints) {
          final itemW = constraints.maxWidth / 4;
          return ListView.builder(
            key: const Key('hero_carousel'),
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _track.length,
            itemExtent: itemW,
            itemBuilder: (_, i) {
              final it = _track[i];
              return _Circle(item: it);
            },
          );
        }),
      ),
    );
  }
}

class _Circle extends StatelessWidget {
  const _Circle({required this.item});

  final HeroCarouselItem item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('hero_item_${item.key}'),
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: .14),
              border: Border.all(color: Colors.white.withValues(alpha: .22)),
            ),
            child: Icon(item.icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 7),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Color(0xFFEAF6FB),
                fontSize: 11.5,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
