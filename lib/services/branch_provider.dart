import 'package:flutter/foundation.dart';
import '../models/branch.dart';

/// ChangeNotifier that holds the **currently active branch** for the
/// authenticated session. All reads (Inventory, Sales, KDS, Employees)
/// must include [currentBranchId] as a `branch_id` query / body param.
///
/// Provide this at the root of the widget tree (above `MaterialApp`) so
/// every screen can `context.watch<BranchProvider>()` or
/// `context.read<BranchProvider>()`.
///
/// Usage:
/// ```dart
/// // Read:
/// final branchId = context.read<BranchProvider>().currentBranchId;
///
/// // Listen:
/// final provider = context.watch<BranchProvider>();
/// Text(provider.currentBranch?.name ?? 'Sin sucursal');
/// ```
class BranchProvider extends ChangeNotifier {
  /// All branches belonging to the current tenant (loaded after login).
  List<Branch> _branches = [];

  /// The branch the user has actively selected. Defaults to the first
  /// default branch; null only before the first fetch completes.
  Branch? _currentBranch;

  bool _loading = false;
  String? _error;

  // ── Public getters ───────────────────────────────────────────────────────

  List<Branch> get branches => List.unmodifiable(_branches);
  Branch? get currentBranch => _currentBranch;

  /// The UUID of the selected branch — pass this on every backend call.
  String? get currentBranchId => _currentBranch?.id;

  /// True while the initial branch list is being fetched from the backend.
  bool get loading => _loading;

  String? get error => _error;

  bool get hasBranches => _branches.isNotEmpty;

  /// True when the tenant has more than one active branch (enables the
  /// branch-selector UI in the drawer / dashboard header).
  bool get isMultiBranch =>
      _branches.where((b) => b.isActive).length > 1;

  // ── Mutations ────────────────────────────────────────────────────────────

  /// Called after login / branch CRUD to populate the list.
  void setBranches(List<Branch> branches) {
    _branches = branches;
    _error = null;
    // If the current selection is no longer valid, fall back to the default.
    if (_currentBranch == null ||
        !branches.any((b) => b.id == _currentBranch!.id)) {
      _currentBranch = branches.firstWhere(
        (b) => b.isDefault && b.isActive,
        orElse: () => branches.isNotEmpty ? branches.first : _currentBranch!,
      );
    }
    notifyListeners();
  }

  /// Switch the active branch. Triggers a rebuild in all listening widgets
  /// so downstream API calls will automatically include the new branch_id.
  void selectBranch(Branch branch) {
    if (_currentBranch?.id == branch.id) return;
    _currentBranch = branch;
    notifyListeners();
  }

  /// Select a branch by its UUID (safe for deep links / push notifications).
  void selectBranchById(String id) {
    final branch = _branches.where((b) => b.id == id).firstOrNull;
    if (branch != null) selectBranch(branch);
  }

  void setLoading(bool value) {
    _loading = value;
    notifyListeners();
  }

  void setError(String? message) {
    _error = message;
    _loading = false;
    notifyListeners();
  }

  /// Add or update a branch in the local list (optimistic UI after CRUD).
  void upsertBranch(Branch branch) {
    final idx = _branches.indexWhere((b) => b.id == branch.id);
    if (idx >= 0) {
      _branches[idx] = branch;
    } else {
      _branches.add(branch);
    }
    notifyListeners();
  }

  /// Remove a branch from the local list. If it was selected, fall back to
  /// the default.
  void removeBranch(String id) {
    _branches.removeWhere((b) => b.id == id);
    if (_currentBranch?.id == id) {
      _currentBranch = _branches.firstWhere(
        (b) => b.isDefault,
        orElse: () => _branches.isNotEmpty ? _branches.first : _currentBranch!,
      );
    }
    notifyListeners();
  }

  /// Clear state on logout.
  void reset() {
    _branches = [];
    _currentBranch = null;
    _error = null;
    _loading = false;
    notifyListeners();
  }
}
