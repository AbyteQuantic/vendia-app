import 'package:flutter/material.dart';

import 'auth_service.dart';

/// Workspace roles. Keep in sync with backend/internal/models/user_workspace.go.
enum WorkspaceRole { owner, admin, cashier, waiter, inventoryManager, unknown }

extension WorkspaceRoleX on WorkspaceRole {
  static WorkspaceRole parse(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'owner':
        return WorkspaceRole.owner;
      case 'admin':
        return WorkspaceRole.admin;
      case 'cashier':
        return WorkspaceRole.cashier;
      case 'waiter':
        return WorkspaceRole.waiter;
      case 'inventory_manager':
        return WorkspaceRole.inventoryManager;
      default:
        return WorkspaceRole.unknown;
    }
  }

  String get label {
    switch (this) {
      case WorkspaceRole.owner:
        return 'Propietario';
      case WorkspaceRole.admin:
        return 'Administrador';
      case WorkspaceRole.cashier:
        return 'Cajero';
      case WorkspaceRole.waiter:
        return 'Mesero';
      case WorkspaceRole.inventoryManager:
        return 'Inventario';
      case WorkspaceRole.unknown:
        return 'Usuario';
    }
  }

  /// Tokens saved before multi-workspace (role == "") are treated as owner
  /// so legacy single-tenant accounts keep full access without a forced
  /// re-login.
  bool get isLegacyOwner => this == WorkspaceRole.unknown;
}

/// Single source of truth for role-based UI gating. Read the stored role once
/// at app boot and expose named permission getters so screens never have to
/// spell out which strings map to which capabilities.
///
/// Example:
///   if (context.watch<RoleManager>().canSeeFinances) ...
class RoleManager extends ChangeNotifier {
  RoleManager(this._auth);

  final AuthService _auth;
  WorkspaceRole _role = WorkspaceRole.unknown;
  bool _loaded = false;

  WorkspaceRole get role => _role;
  bool get isLoaded => _loaded;

  /// Load the role from secure storage. Call once at app startup and again
  /// after login / workspace switch.
  Future<void> refresh() async {
    final raw = await _auth.getRole();
    _role = WorkspaceRoleX.parse(raw);
    _loaded = true;
    notifyListeners();
  }

  void clear() {
    _role = WorkspaceRole.unknown;
    _loaded = false;
    notifyListeners();
  }

  // ── Buckets of capabilities ────────────────────────────────────────────
  // Legacy tokens (no role claim) fall back to full-access so existing
  // merchants keep using the app without a disruptive re-login.

  bool get _isOwnerLike =>
      _role == WorkspaceRole.owner ||
      _role == WorkspaceRole.admin ||
      _role.isLegacyOwner;

  bool get canSeeFinances => _isOwnerLike;
  bool get canManageBusinessSettings => _isOwnerLike;
  bool get canManageEmployees => _isOwnerLike;
  bool get canVoidPastSales => _isOwnerLike;
  bool get canDeleteTenant => _role == WorkspaceRole.owner || _role.isLegacyOwner;

  bool get canSell =>
      _isOwnerLike ||
      _role == WorkspaceRole.cashier ||
      _role == WorkspaceRole.waiter;

  bool get canGrantFiadoWithoutPin => _isOwnerLike;
  bool get canAddProducts =>
      _isOwnerLike ||
      _role == WorkspaceRole.cashier ||
      _role == WorkspaceRole.inventoryManager;
  bool get canManageInventory =>
      _isOwnerLike || _role == WorkspaceRole.inventoryManager;

  bool get canUsePanicButton => true; // safety-critical — everyone can.

  bool get canApplyPromotions =>
      _isOwnerLike ||
      _role == WorkspaceRole.cashier ||
      _role == WorkspaceRole.waiter;
  bool get canEditPromotions => _isOwnerLike;
}
