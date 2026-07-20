// Spec: specs/106-onboarding-conversacional-agente/spec.md
//
// Estado de la conversación con Vendi. El backend conduce la máquina de
// estados; este controller solo refleja la respuesta de cada turno, guarda el
// session_id para retomar (AC-11) y bloquea el doble envío mientras hay un
// turno en vuelo. Las llamadas se inyectan como funciones para poder probarlo
// sin red ni ApiService.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef VendiTurnCall = Future<Map<String, dynamic>> Function({
  String? sessionId,
  String? text,
  String? chip,
  String? kind,
});
typedef VendiConfirmCall = Future<Map<String, dynamic>> Function(
    String sessionId);

enum VendiRole { assistant, user }

/// Un mensaje del hilo. Los del asistente pueden traer chips y propuesta.
class VendiMessage {
  VendiMessage({required this.role, required this.text});

  final VendiRole role;
  final String text;
}

class VendiChip {
  const VendiChip({required this.id, required this.label});

  final String id;
  final String label;
}

class VendiProfileType {
  const VendiProfileType(
      {required this.key, required this.label, required this.primary});

  final String key;
  final String label;
  final bool primary;
}

class VendiChatController extends ChangeNotifier {
  VendiChatController({
    required VendiTurnCall turnCall,
    required VendiConfirmCall confirmCall,
    this.persist = true,
    this.kind = 'onboarding',
  })  : _turnCall = turnCall,
        _confirmCall = confirmCall;

  /// 'onboarding' (Spec 106) | 'assist' (Spec 107, botón central).
  final String kind;

  static const prefsKey = 'vendia:vendi:session';

  String get _prefsKeyForKind =>
      kind == 'onboarding' ? prefsKey : '$prefsKey:$kind';

  final VendiTurnCall _turnCall;
  final VendiConfirmCall _confirmCall;
  final bool persist;

  final List<VendiMessage> messages = [];
  List<VendiChip> chips = const [];
  List<VendiProfileType> profileTypes = const [];
  Map<String, bool> attrs = const {};
  List<String> proposalGrid = const [];
  List<String> proposalReel = const [];

  String? sessionId;
  String phase = '';

  /// Follow-up en curso (Adenda A): matiza la forma/gesto del orbe.
  String pendingKey = '';
  bool age18 = false;
  bool busy = false;
  bool degraded = false;
  bool offerFallback = false;
  bool done = false;

  /// Spec 107 — resultado de la última acción assist ejecutada
  /// ({ok, entity, id, route, say}); null si el turno no ejecutó nada.
  Map<String, dynamic>? actionResult;

  /// Primer contacto o reanudación: manda un turno vacío. El backend saluda
  /// (sesión nueva) o re-emite la pregunta pendiente (sesión activa).
  Future<void> start() async {
    if (persist) {
      try {
        final prefs = await SharedPreferences.getInstance();
        sessionId = prefs.getString(_prefsKeyForKind);
      } catch (_) {}
    }
    await _runTurn();
  }

  Future<void> sendText(String text) async {
    final t = text.trim();
    if (t.isEmpty || busy) return;
    messages.add(VendiMessage(role: VendiRole.user, text: t));
    notifyListeners();
    await _runTurn(text: t);
  }

  Future<void> tapChip(String id, String label) async {
    if (busy) return;
    messages.add(VendiMessage(role: VendiRole.user, text: label));
    notifyListeners();
    if (id == 'confirm') {
      await _confirm();
      return;
    }
    await _runTurn(chip: id);
  }

  /// Reintenta el último estado tras un turno degradado.
  Future<void> retry() => _runTurn();

  Future<void> _confirm() async {
    final sid = sessionId;
    if (sid == null || sid.isEmpty) return;
    busy = true;
    chips = const [];
    notifyListeners();
    try {
      final res = await _confirmCall(sid);
      if (res['degraded'] == true) {
        degraded = true;
        messages.add(VendiMessage(
          role: VendiRole.assistant,
          text:
              'No pude guardar la configuración. Revise su conexión e intente de nuevo. 🙏',
        ));
        chips = const [VendiChip(id: 'confirm', label: 'Intentar de nuevo')];
        return;
      }
      done = true;
      degraded = false;
      messages.add(VendiMessage(
        role: VendiRole.assistant,
        text:
            '¡Su tienda quedó lista! 🎉 Cuando quiera cambiar algo, me dice — estaré aquí en su panel. 💙',
      ));
      await _clearSession();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _runTurn({String? text, String? chip}) async {
    if (busy) return;
    busy = true;
    degraded = false;
    chips = const [];
    notifyListeners();
    try {
      final res =
          await _turnCall(sessionId: sessionId, text: text, chip: chip, kind: kind);
      _apply(res);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _apply(Map<String, dynamic> res) {
    actionResult = (res['action_result'] is Map)
        ? Map<String, dynamic>.from(res['action_result'] as Map)
        : null;
    if (res['degraded'] == true) {
      degraded = true;
      offerFallback = res['offer_fallback'] == true || offerFallback;
      return;
    }

    final sid = res['session_id'] as String?;
    if (sid != null && sid.isNotEmpty && sid != sessionId) {
      sessionId = sid;
      _persistSession(sid);
    }
    phase = (res['phase'] as String?) ?? phase;
    pendingKey = (res['pending_key'] as String?) ?? '';
    done = res['done'] == true;
    offerFallback = res['offer_fallback'] == true;

    for (final s in (res['say'] as List? ?? const [])) {
      final t = s.toString();
      if (t.isNotEmpty) {
        messages.add(VendiMessage(role: VendiRole.assistant, text: t));
      }
    }
    chips = [
      for (final c in (res['chips'] as List? ?? const []))
        VendiChip(
          id: (c as Map)['id'].toString(),
          label: c['label'].toString(),
        ),
    ];

    final profile = res['profile'];
    if (profile is Map) {
      age18 = profile['age18'] == true;
      profileTypes = [
        for (final t in (profile['types'] as List? ?? const []))
          VendiProfileType(
            key: (t as Map)['key'].toString(),
            label: (t['label'] ?? t['key']).toString(),
            primary: t['primary'] == true,
          ),
      ];
      attrs = {
        for (final e in ((profile['attrs'] as Map?) ?? const {}).entries)
          e.key.toString(): e.value == true,
      };
    }
    final proposal = res['proposal'];
    if (proposal is Map) {
      proposalGrid = [
        for (final g in (proposal['grid'] as List? ?? const [])) g.toString()
      ];
      proposalReel = [
        for (final r in (proposal['reel'] as List? ?? const [])) r.toString()
      ];
    }
    if (done) _clearSession();
  }

  void _persistSession(String sid) {
    if (!persist) return;
    SharedPreferences.getInstance()
        .then((p) => p.setString(_prefsKeyForKind, sid))
        .catchError((_) => true);
  }

  Future<void> _clearSession() async {
    if (!persist) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKeyForKind);
    } catch (_) {}
  }
}
