// Spec: specs/042-modulo-eventos/spec.md
//
// Editor de descripción del evento a PANTALLA COMPLETA (mobile-first). El
// diálogo pequeño anterior era incómodo: poco espacio y texto difícil de leer.
// Aquí el texto llena la pantalla, con ajuste de tamaño de letra (A−/A+) para
// comodidad (gerontodiseño 50+) y atajos para estructurar (viñetas, secciones).
// Devuelve el texto editado por Navigator.pop (o null si se cancela).

import 'package:flutter/material.dart';

const _eventAccent = Color(0xFF0EA5E9);

class EventDescriptionEditorScreen extends StatefulWidget {
  final String initialText;
  const EventDescriptionEditorScreen({super.key, this.initialText = ''});

  @override
  State<EventDescriptionEditorScreen> createState() =>
      _EventDescriptionEditorScreenState();
}

class _EventDescriptionEditorScreenState
    extends State<EventDescriptionEditorScreen> {
  late final TextEditingController _ctrl;
  final _focus = FocusNode();
  double _fontSize = 16;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _adjustFont(double delta) {
    setState(() => _fontSize = (_fontSize + delta).clamp(13.0, 26.0));
  }

  /// Envuelve la selección con [wrapper] (p. ej. "**" para negrita). Sin
  /// selección, inserta el par y deja el cursor en el medio para escribir.
  void _wrapSelection(String wrapper) {
    final sel = _ctrl.selection;
    final text = _ctrl.text;
    final start = sel.start >= 0 ? sel.start : text.length;
    final end = sel.end >= 0 ? sel.end : start;
    final selected = text.substring(start, end);
    final wrapped = '$wrapper$selected$wrapper';
    final newText = text.replaceRange(start, end, wrapped);
    final cursor =
        selected.isEmpty ? start + wrapper.length : start + wrapped.length;
    _ctrl.value = _ctrl.value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: cursor),
      composing: TextRange.empty,
    );
    _focus.requestFocus();
  }

  /// Inserta [snippet] en la posición del cursor (o al final) y mantiene el
  /// foco para seguir escribiendo.
  void _insert(String snippet) {
    final sel = _ctrl.selection;
    final text = _ctrl.text;
    final start = sel.start >= 0 ? sel.start : text.length;
    final end = sel.end >= 0 ? sel.end : start;
    // Las viñetas y títulos van al inicio de su renglón: si no estamos al
    // inicio de línea, anteponer un salto.
    var s = snippet;
    final isLinePrefix = snippet.startsWith('• ') || snippet.startsWith('## ');
    if (isLinePrefix && start > 0 && text[start - 1] != '\n') {
      s = '\n$snippet';
    }
    final newText = text.replaceRange(start, end, s);
    _ctrl.value = _ctrl.value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: start + s.length),
      composing: TextRange.empty,
    );
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Descripción del evento'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              key: const Key('desc_editor_save'),
              style: FilledButton.styleFrom(backgroundColor: _eventAccent),
              onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()),
              child: const Text('Guardar'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _toolbar(),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                key: const Key('desc_editor_field'),
                controller: _ctrl,
                focusNode: _focus,
                autofocus: true,
                expands: true,
                maxLines: null,
                minLines: null,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                textAlignVertical: TextAlignVertical.top,
                style: TextStyle(fontSize: _fontSize, height: 1.45),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText:
                      'De qué trata, qué incluye, duración/horas, temario, '
                      'requisitos previos, a quién va dirigido…\n\n'
                      'Usa los botones de arriba para viñetas y secciones.',
                ),
              ),
            ),
          ),
          _footer(),
        ],
      ),
    );
  }

  Widget _toolbar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          _toolBtn(
            icon: Icons.text_decrease_rounded,
            tooltip: 'Reducir texto',
            onTap: () => _adjustFont(-1),
          ),
          _toolBtn(
            icon: Icons.text_increase_rounded,
            tooltip: 'Agrandar texto',
            onTap: () => _adjustFont(1),
          ),
          const _ToolDivider(),
          _toolChip(
            key: const Key('desc_editor_bold'),
            icon: Icons.format_bold_rounded,
            label: 'Negrita',
            onTap: () => _wrapSelection('**'),
          ),
          _toolChip(
            key: const Key('desc_editor_title'),
            icon: Icons.title_rounded,
            label: 'Título',
            onTap: () => _insert('## '),
          ),
          _toolChip(
            key: const Key('desc_editor_bullet'),
            icon: Icons.format_list_bulleted_rounded,
            label: 'Viñeta',
            onTap: () => _insert('• '),
          ),
        ],
      ),
    );
  }

  Widget _toolBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, color: _eventAccent),
    );
  }

  Widget _toolChip({
    Key? key,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ActionChip(
        key: key,
        avatar: Icon(icon, size: 18, color: _eventAccent),
        label: Text(label),
        onPressed: onTap,
        side: BorderSide(color: Colors.grey.shade300),
        backgroundColor: Colors.white,
      ),
    );
  }

  Widget _footer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Se muestra en el link del catálogo y le da contexto a la IA.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
              ),
            ),
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => Text('${_ctrl.text.characters.length}',
                  style:
                      TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolDivider extends StatelessWidget {
  const _ToolDivider();
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: Colors.grey.shade300,
      );
}
