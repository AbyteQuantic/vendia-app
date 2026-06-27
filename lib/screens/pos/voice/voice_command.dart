// Spec: specs/085-vender-por-voz/spec.md
//
// DTOs del flujo "vender por voz". fromJson DEFENSIVO: nunca lanzan; campos
// faltantes/nulos o tipos raros caen a valores seguros (el sobre degradado tiene
// commands vacío). El front nunca confía ciegamente en el LLM.

enum VoiceAction {
  agregar,
  quitar,
  fijarCantidad,
  vaciar,
  fijarMesa,
  fijarCliente,
  cobrar,
  desconocido,
}

VoiceAction voiceActionFromString(String? s) {
  switch ((s ?? '').trim().toLowerCase()) {
    case 'agregar':
      return VoiceAction.agregar;
    case 'quitar':
      return VoiceAction.quitar;
    case 'fijar_cantidad':
      return VoiceAction.fijarCantidad;
    case 'vaciar':
      return VoiceAction.vaciar;
    case 'fijar_mesa':
      return VoiceAction.fijarMesa;
    case 'fijar_cliente':
      return VoiceAction.fijarCliente;
    case 'cobrar':
      return VoiceAction.cobrar;
    default:
      return VoiceAction.desconocido;
  }
}

enum VoiceTargetType { mesa, cliente, mostrador }

class VoiceTarget {
  final VoiceTargetType type;
  final String? mesa;
  final String? cliente;

  const VoiceTarget({required this.type, this.mesa, this.cliente});

  static VoiceTarget? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final t = (raw['type'] as String?)?.trim().toLowerCase();
    final type = switch (t) {
      'mesa' => VoiceTargetType.mesa,
      'cliente' => VoiceTargetType.cliente,
      _ => VoiceTargetType.mostrador,
    };
    String? str(Object? v) {
      final s = (v as String?)?.trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return VoiceTarget(type: type, mesa: str(raw['mesa']), cliente: str(raw['cliente']));
  }
}

class VoiceCommand {
  final VoiceAction action;
  final String? item; // nombre hablado (lower, sin tildes)
  final int? quantity;
  final VoiceTarget? target;
  final double confidence;
  final String? clarifyPrompt;
  final String raw;

  const VoiceCommand({
    required this.action,
    this.item,
    this.quantity,
    this.target,
    this.confidence = 0.0,
    this.clarifyPrompt,
    this.raw = '',
  });

  static VoiceCommand fromJson(Object? raw) {
    if (raw is! Map) {
      return const VoiceCommand(action: VoiceAction.desconocido);
    }
    String? str(Object? v) {
      final s = (v as String?)?.trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    int? qty;
    final q = raw['quantity'];
    if (q is int) {
      qty = q;
    } else if (q is double) {
      qty = q.round();
    } else if (q is String) {
      qty = int.tryParse(q.trim());
    }
    if (qty != null && qty < 0) qty = 0;

    double conf = 0.0;
    final c = raw['confidence'];
    if (c is num) conf = c.toDouble().clamp(0.0, 1.0);

    return VoiceCommand(
      action: voiceActionFromString(raw['action'] as String?),
      item: str(raw['item']),
      quantity: qty,
      target: VoiceTarget.fromJson(raw['target']),
      confidence: conf,
      clarifyPrompt: str(raw['clarify_prompt']),
      raw: str(raw['raw']) ?? '',
    );
  }
}

class VoiceOrderResult {
  final List<VoiceCommand> commands;
  final String transcript;
  final String? clarifyPrompt;
  final bool degraded;

  const VoiceOrderResult({
    this.commands = const [],
    this.transcript = '',
    this.clarifyPrompt,
    this.degraded = false,
  });

  /// Tolerante: cualquier forma rara → degraded con commands vacío (nunca lanza).
  static VoiceOrderResult fromJson(Object? raw) {
    if (raw is! Map) {
      return const VoiceOrderResult(degraded: true);
    }
    final rawCmds = raw['commands'];
    final cmds = <VoiceCommand>[];
    if (rawCmds is List) {
      for (final e in rawCmds) {
        final cmd = VoiceCommand.fromJson(e);
        if (cmd.action != VoiceAction.desconocido) cmds.add(cmd);
      }
    }
    final clarify = (raw['clarify_prompt'] as String?)?.trim();
    return VoiceOrderResult(
      commands: cmds,
      transcript: (raw['transcript'] as String?)?.trim() ?? '',
      clarifyPrompt: (clarify == null || clarify.isEmpty) ? null : clarify,
      degraded: raw['degraded'] == true,
    );
  }
}
