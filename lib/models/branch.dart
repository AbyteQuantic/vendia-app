/// Branch (Sucursal) model for multi-tenant multi-branch SaaS architecture.
/// Each Tenant (negocio) has one or more Branches.
/// All inventory, employee assignments, sales and KDS reads are
/// scoped to the currently-selected Branch.
class Branch {
  final String id; // UUID from backend
  final String tenantId;
  final String name; // "Sede Principal", "Sede Norte", etc.
  final String? address;
  final double? latitude;
  final double? longitude;
  final bool isDefault; // The auto-created branch on tenant registration
  final bool isActive;
  final DateTime createdAt;

  const Branch({
    required this.id,
    required this.tenantId,
    required this.name,
    this.address,
    this.latitude,
    this.longitude,
    this.isDefault = false,
    this.isActive = true,
    required this.createdAt,
  });

  factory Branch.fromJson(Map<String, dynamic> json) {
    return Branch(
      id: json['id'] as String? ?? json['uuid'] as String,
      tenantId: json['tenant_id'] as String? ?? '',
      name: json['name'] as String,
      address: json['address'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      isDefault: json['is_default'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'is_default': isDefault,
        'is_active': isActive,
      };

  Branch copyWith({
    String? name,
    String? address,
    double? latitude,
    double? longitude,
    bool? isActive,
  }) {
    return Branch(
      id: id,
      tenantId: tenantId,
      name: name ?? this.name,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isDefault: isDefault,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Branch && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Branch(id: $id, name: $name)';
}
