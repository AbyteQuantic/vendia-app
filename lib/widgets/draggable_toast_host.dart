// Spec: specs/056-notificaciones-cta-toast-push/spec.md
import 'package:flutter/material.dart';

import 'notification_toast.dart';

/// DraggableToastHost — monta el toast como un overlay que el usuario puede
/// MOVER (arrastrar verticalmente) para que no le tape la información de la
/// pantalla. Por default queda arriba (bajo la barra de estado) y, si estorba,
/// se desliza a un espacio libre. Recuerda la posición que el usuario eligió.
/// Devuelve un Positioned para vivir directo dentro del Stack del MaterialApp.builder.
class DraggableToastHost extends StatefulWidget {
  const DraggableToastHost({super.key});

  @override
  State<DraggableToastHost> createState() => _DraggableToastHostState();
}

class _DraggableToastHostState extends State<DraggableToastHost> {
  // Desplazamiento vertical manual (null = posición por default, arriba).
  double? _top;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final topSafe = media.padding.top + 6;
    final maxTop = media.size.height - 180; // no dejarlo salir por abajo
    final top = (_top ?? topSafe).clamp(topSafe, maxTop > topSafe ? maxTop : topSafe);

    return Positioned(
      left: 12,
      right: 12,
      top: top,
      child: GestureDetector(
        // El arrastre vertical mueve el toast; los toques en CTA/X siguen
        // funcionando (los maneja el hijo). El "agarre" lo da el cuerpo del toast.
        behavior: HitTestBehavior.deferToChild,
        onVerticalDragUpdate: (d) {
          setState(() {
            _top = ((_top ?? topSafe) + d.delta.dy).clamp(topSafe, maxTop > topSafe ? maxTop : topSafe);
          });
        },
        child: const _ToastWithGrip(),
      ),
    );
  }
}

/// Agrega un asita sutil arriba del toast para que se note que se puede mover.
/// Si no hay toast visible, NotificationToast devuelve SizedBox.shrink → no se
/// dibuja nada (ni el agarre).
class _ToastWithGrip extends StatelessWidget {
  const _ToastWithGrip();

  @override
  Widget build(BuildContext context) {
    return const NotificationToast(grip: true);
  }
}
