import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../dashboard/dashboard_screen.dart';

/// Workspace info passed from login response.
class WorkspaceInfo {
  final String workspaceId;
  final String tenantId;
  final String tenantName;
  final String branchId;
  final String branchName;
  final String role;

  const WorkspaceInfo({
    required this.workspaceId,
    required this.tenantId,
    required this.tenantName,
    this.branchId = '',
    this.branchName = '',
    required this.role,
  });

  factory WorkspaceInfo.fromJson(Map<String, dynamic> json) {
    return WorkspaceInfo(
      workspaceId: json['workspace_id'] as String? ?? '',
      tenantId: json['tenant_id'] as String? ?? '',
      tenantName: json['tenant_name'] as String? ?? 'Sin nombre',
      branchId: json['branch_id'] as String? ?? '',
      branchName: json['branch_name'] as String? ?? '',
      role: json['role'] as String? ?? 'cashier',
    );
  }

  bool get isOwner => role == 'owner';
  String get roleLabel => switch (role) {
        'owner' => 'Propietario',
        'admin' => 'Administrador',
        'cashier' => 'Cajero',
        'waiter' => 'Mesero',
        _ => role,
      };
}

/// Post-login workspace selector — Gerontodiseño.
/// Shown when user has access to multiple businesses.
class WorkspaceSelectorScreen extends StatefulWidget {
  final List<WorkspaceInfo> workspaces;
  final String userName;
  final String tempToken;

  const WorkspaceSelectorScreen({
    super.key,
    required this.workspaces,
    required this.userName,
    required this.tempToken,
  });

  @override
  State<WorkspaceSelectorScreen> createState() =>
      _WorkspaceSelectorScreenState();
}

class _WorkspaceSelectorScreenState extends State<WorkspaceSelectorScreen> {
  late final AuthService _auth;
  late final ApiService _api;
  bool _selecting = false;
  String? _selectingId;

  @override
  void initState() {
    super.initState();
    _auth = AuthService();
    _api = ApiService(_auth);
  }

  Future<void> _onWorkspaceTap(WorkspaceInfo ws) async {
    if (_selecting) return;
    setState(() {
      _selecting = true;
      _selectingId = ws.workspaceId;
    });
    HapticFeedback.lightImpact();

    try {
      final data = await _api.selectWorkspace(
        workspaceId: ws.workspaceId,
        tempToken: widget.tempToken,
      );

      await _auth.saveWorkspaceSession(
        accessToken: data['token'] as String,
        refreshToken: data['refresh_token'] as String? ?? '',
        tenantId: data['tenant_id'] as String? ?? ws.tenantId,
        ownerName: data['owner_name'] as String? ?? widget.userName,
        businessName: data['business_name'] as String? ?? ws.tenantName,
        role: ws.role,
        branchId: ws.branchId,
      );

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, animation, __) => DashboardScreen(
            ownerName: widget.userName,
            businessName: ws.tenantName,
          ),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity:
                CurvedAnimation(parent: animation, curve: Curves.easeInOut),
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _selecting = false;
          _selectingId = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e', style: const TextStyle(fontSize: 16)),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF7),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.point_of_sale_rounded,
                        color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  const Text('VendIA',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary)),
                ],
              ),
              const SizedBox(height: 28),

              Text('Hola, ${widget.userName}',
                  style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 8),
              Text(
                '¿A qué negocio vamos a entrar?',
                style: TextStyle(
                    fontSize: 20,
                    color: Colors.grey.shade600,
                    height: 1.4),
              ),
              const SizedBox(height: 28),

              // Workspace list
              Expanded(
                child: ListView.separated(
                  itemCount: widget.workspaces.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final ws = widget.workspaces[index];
                    final isSelecting = _selectingId == ws.workspaceId;

                    return GestureDetector(
                      onTap: () => _onWorkspaceTap(ws),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isSelecting
                              ? AppTheme.primary.withValues(alpha: 0.06)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: isSelecting
                                ? AppTheme.primary
                                : AppTheme.borderColor,
                            width: isSelecting ? 2 : 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            // Role icon
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: ws.isOwner
                                    ? const Color(0xFFFEF3C7)
                                    : AppTheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Center(
                                child: Text(
                                  ws.isOwner ? '\u{1F451}' : '\u{1F4BC}',
                                  style: const TextStyle(fontSize: 28),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),

                            // Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(ws.tenantName,
                                      style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.textPrimary)),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: ws.isOwner
                                              ? const Color(0xFFFEF3C7)
                                              : const Color(0xFFE0E7FF),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(ws.roleLabel,
                                            style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: ws.isOwner
                                                    ? const Color(0xFF92400E)
                                                    : AppTheme.primary)),
                                      ),
                                      if (ws.branchName.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(ws.branchName,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 14,
                                                  color:
                                                      AppTheme.textSecondary)),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // Arrow or spinner
                            if (isSelecting)
                              const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      color: AppTheme.primary, strokeWidth: 2))
                            else
                              const Icon(Icons.chevron_right_rounded,
                                  size: 32, color: AppTheme.primary),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
