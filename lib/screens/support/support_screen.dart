import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

import '../../config/api_config.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _api = ApiService(AuthService());
  
  bool _loading = true;
  List<Map<String, dynamic>> _tickets = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTickets();
  }

  Future<void> _loadTickets() async {
    setState(() => _loading = true);
    try {
      final res = await _api.fetchTenantTickets();
      if (mounted) {
        setState(() {
          _tickets = res;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'No se pudieron cargar los tickets';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Ayuda y Soporte',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
      ),
      body: _loading 
        ? const Center(child: CircularProgressIndicator())
        : _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: AppTheme.error)))
          : RefreshIndicator(
              onRefresh: _loadTickets,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    'Mis Tickets',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 12),
                  if (_tickets.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Text('No tienes tickets abiertos. Si necesitas ayuda, crea uno nuevo.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    )
                  else
                    ..._tickets.map((t) => _TicketCard(ticket: t, onTap: () => _openTicket(t))),
                  
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _createNewTicket,
                    icon: const Icon(Icons.add_comment_rounded),
                    label: const Text('Crear Nuevo Ticket'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _openWhatsapp,
                    icon: const Icon(Icons.chat_rounded, size: 22),
                    label: const Text('Chat por WhatsApp'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF16A34A),
                      side: const BorderSide(color: Color(0xFF16A34A)),
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  void _openTicket(Map<String, dynamic> ticket) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TicketDetailScreen(ticketId: ticket['id'])),
    ).then((_) => _loadTickets());
  }

  void _createNewTicket() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreateTicketScreen()),
    ).then((_) => _loadTickets());
  }

  Future<void> _openWhatsapp() async {
    final number = ApiConfig.supportWhatsappNumber;
    final uri = Uri.parse(
      'https://wa.me/$number?text=${Uri.encodeComponent('Hola, necesito soporte con VendIA')}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _TicketCard extends StatelessWidget {
  final Map<String, dynamic> ticket;
  final VoidCallback onTap;

  const _TicketCard({required this.ticket, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = ticket['status'] ?? 'OPEN';
    final priority = ticket['priority'] ?? 'NORMAL';
    final category = ticket['category'] ?? 'OTHER';
    final date = DateTime.parse(ticket['created_at']);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Badge(text: category, color: Colors.grey.shade100, textColor: Colors.grey.shade600),
                  const Spacer(),
                  _PriorityBadge(priority: priority),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                ticket['subject'] ?? 'Sin asunto',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _StatusBadge(status: status),
                  const Spacer(),
                  Text(
                    DateFormat('dd MMM, HH:mm').format(date.toLocal()),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Create Ticket Screen ───────────────────────────────────────────────────

class CreateTicketScreen extends StatefulWidget {
  const CreateTicketScreen({super.key});

  @override
  State<CreateTicketScreen> createState() => _CreateTicketScreenState();
}

class _CreateTicketScreenState extends State<CreateTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  String _category = 'BUG';
  bool _submitting = false;

  final categories = {
    'BUG': 'Reportar un error',
    'BILLING': 'Facturación y Pagos',
    'FEATURE': 'Sugerir una función',
    'OTHER': 'Otro motivo',
  };

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await ApiService(AuthService()).createSupportTicket(
        subject: _subjectCtrl.text.trim(),
        message: _messageCtrl.text.trim(),
        category: _category,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al crear ticket')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Nuevo Ticket')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Asunto', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _subjectCtrl,
                decoration: const InputDecoration(hintText: 'Ej. No carga el inventario'),
                validator: (v) => v!.isEmpty ? 'Campo requerido' : null,
              ),
              const SizedBox(height: 20),
              const Text('Categoría', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _category,
                items: categories.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                onChanged: (v) => setState(() => _category = v!),
              ),
              const SizedBox(height: 20),
              const Text('Descripción', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _messageCtrl,
                maxLines: 5,
                decoration: const InputDecoration(hintText: 'Describe detalladamente tu problema...'),
                validator: (v) => v!.isEmpty ? 'Campo requerido' : null,
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                child: _submitting ? const CircularProgressIndicator(color: Colors.white) : const Text('Crear Ticket'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Ticket Detail Screen (Conversation) ────────────────────────────────────

class TicketDetailScreen extends StatefulWidget {
  final String ticketId;
  const TicketDetailScreen({super.key, required this.ticketId});

  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  final _api = ApiService(AuthService());
  final _msgCtrl = TextEditingController();
  final _scroll = ScrollController();
  
  Map<String, dynamic>? _ticket;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _api.fetchTicketDetails(widget.ticketId);
      if (mounted) {
        setState(() {
          _ticket = res;
          _loading = false;
        });
        Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrollToBottom() {
    if (_scroll.hasClients) {
      _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  Future<void> _send() async {
    if (_msgCtrl.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await _api.addTicketMessage(widget.ticketId, _msgCtrl.text.trim());
      _msgCtrl.clear();
      await _load();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_ticket == null) return const Scaffold(body: Center(child: Text('Error')));

    final messages = (_ticket!['messages'] as List?) ?? [];

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_ticket!['subject'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(_ticket!['status'], style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: messages.length,
              itemBuilder: (context, i) {
                final m = messages[i];
                final isAdmin = m['sender_type'] == 'ADMIN';
                return _ChatBubble(
                  content: m['content'],
                  isAdmin: isAdmin,
                  time: DateFormat('HH:mm').format(DateTime.parse(m['created_at']).toLocal()),
                );
              },
            ),
          ),
          if (_ticket!['status'] != 'RESOLVED')
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE5E7EB)))),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    decoration: InputDecoration(
                      hintText: 'Responder...',
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _sending ? null : _send,
                  icon: const Icon(Icons.send_rounded, color: AppTheme.primary),
                ),
              ],
            ),
          )
          else
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Este ticket está resuelto. Crea uno nuevo si necesitas más ayuda.', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final String content;
  final bool isAdmin;
  final String time;

  const _ChatBubble({required this.content, required this.isAdmin, required this.time});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isAdmin ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isAdmin ? Colors.grey.shade200 : AppTheme.primary,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isAdmin ? 0 : 16),
            bottomRight: Radius.circular(isAdmin ? 16 : 0),
          ),
        ),
        child: Column(
          crossAxisAlignment: isAdmin ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            Text(content, style: TextStyle(color: isAdmin ? Colors.black87 : Colors.white, fontSize: 15)),
            const SizedBox(height: 4),
            Text(time, style: TextStyle(color: isAdmin ? Colors.black38 : Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

// ── Components ─────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  final Color textColor;
  const _Badge({required this.text, required this.color, required this.textColor});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  final String priority;
  const _PriorityBadge({required this.priority});
  @override
  Widget build(BuildContext context) {
    Color color = Colors.grey.shade100;
    Color text = Colors.grey.shade600;
    if (priority == 'HIGH') { color = Colors.amber.shade100; text = Colors.amber.shade700; }
    if (priority == 'URGENT') { color = Colors.red.shade100; text = Colors.red.shade700; }
    return _Badge(text: priority, color: color, textColor: text);
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});
  @override
  Widget build(BuildContext context) {
    Color color = Colors.blue.shade100;
    Color text = Colors.blue.shade700;
    if (status == 'RESOLVED') { color = Colors.green.shade100; text = Colors.green.shade700; }
    if (status == 'IN_PROGRESS') { color = Colors.purple.shade100; text = Colors.purple.shade700; }
    return _Badge(text: status, color: color, textColor: text);
  }
}
