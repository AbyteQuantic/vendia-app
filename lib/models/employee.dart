/// Employee model for VendIA POS system.
/// Supports 2 roles: admin (owner) and cashier (employee).
class Employee {
  final String uuid;
  final String name;
  final String pin; // 4-digit PIN for authentication
  final EmployeeRole role;
  final bool isActive;
  final bool isOwner;
  final DateTime createdAt;
  final int? serverId;

  Employee({
    required this.uuid,
    required this.name,
    required this.pin,
    this.role = EmployeeRole.cashier,
    this.isActive = true,
    this.isOwner = false,
    DateTime? createdAt,
    this.serverId,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Initials for avatar display (e.g., "PM" for "Pedro Martínez")
  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  /// Role display label in Spanish
  String get roleLabel => role == EmployeeRole.admin ? 'Administrador' : 'Cajero';

  /// Role description for UI
  String get roleDescription => role == EmployeeRole.admin
      ? 'Acceso total: ventas, reportes, configuración'
      : 'Solo puede vender y fiar';

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      uuid: json['uuid'] as String,
      name: json['name'] as String,
      pin: json['pin'] as String? ?? '',
      role: json['role'] == 'admin' ? EmployeeRole.admin : EmployeeRole.cashier,
      isActive: json['is_active'] as bool? ?? true,
      isOwner: json['is_owner'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      serverId: json['id'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'name': name,
        'pin': pin,
        'role': role == EmployeeRole.admin ? 'admin' : 'cashier',
        'is_active': isActive,
        'is_owner': isOwner,
      };

  Employee copyWith({
    String? name,
    String? pin,
    EmployeeRole? role,
    bool? isActive,
  }) {
    return Employee(
      uuid: uuid,
      name: name ?? this.name,
      pin: pin ?? this.pin,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      isOwner: isOwner,
      createdAt: createdAt,
      serverId: serverId,
    );
  }
}

enum EmployeeRole { admin, cashier }
