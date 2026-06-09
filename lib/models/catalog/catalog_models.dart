// Spec: specs/041-catalogo-dinamico-modulos-tipos/spec.md
//
// Modelos del catálogo dinámico (F041) que la app consume desde
// GET /api/v1/catalog. Inmutables; se parsean del JSON del backend y se
// cachean para uso offline-first.

class CatalogModule {
  final String id;
  final String key;
  final String name;
  final String description;
  final String iconKey;
  final String color;
  final String category;
  final String renderType; // native | webview | placeholder
  final String? nativeScreenKey;
  final String? webviewUrl;
  final String? capabilityKey;
  final bool requiresPro;
  final bool active;
  final int sortOrder;

  const CatalogModule({
    required this.id,
    required this.key,
    required this.name,
    required this.description,
    required this.iconKey,
    required this.color,
    required this.category,
    required this.renderType,
    required this.nativeScreenKey,
    required this.webviewUrl,
    required this.capabilityKey,
    required this.requiresPro,
    required this.active,
    required this.sortOrder,
  });

  factory CatalogModule.fromJson(Map<String, dynamic> j) => CatalogModule(
        id: (j['id'] ?? '').toString(),
        key: (j['key'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        iconKey: (j['icon_key'] ?? '').toString(),
        color: (j['color'] ?? '').toString(),
        category: (j['category'] ?? '').toString(),
        renderType: (j['render_type'] ?? 'native').toString(),
        nativeScreenKey: j['native_screen_key'] as String?,
        webviewUrl: j['webview_url'] as String?,
        capabilityKey: j['capability_key'] as String?,
        requiresPro: j['requires_pro'] == true,
        active: j['active'] == true,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'key': key,
        'name': name,
        'description': description,
        'icon_key': iconKey,
        'color': color,
        'category': category,
        'render_type': renderType,
        'native_screen_key': nativeScreenKey,
        'webview_url': webviewUrl,
        'capability_key': capabilityKey,
        'requires_pro': requiresPro,
        'active': active,
        'sort_order': sortOrder,
      };
}

class CatalogTypeEntry {
  final String value;
  final String label;
  final String iconKey;
  final bool active;
  final int sortOrder;

  const CatalogTypeEntry({
    required this.value,
    required this.label,
    required this.iconKey,
    required this.active,
    required this.sortOrder,
  });

  factory CatalogTypeEntry.fromJson(Map<String, dynamic> j) => CatalogTypeEntry(
        value: (j['value'] ?? '').toString(),
        label: (j['label'] ?? '').toString(),
        iconKey: (j['icon_key'] ?? '').toString(),
        active: j['active'] == true,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'value': value,
        'label': label,
        'icon_key': iconKey,
        'active': active,
        'sort_order': sortOrder,
      };
}

class CatalogRelation {
  final String moduleId;
  final String businessTypeValue;
  final String relationLevel; // implicit | suggested | available

  const CatalogRelation({
    required this.moduleId,
    required this.businessTypeValue,
    required this.relationLevel,
  });

  factory CatalogRelation.fromJson(Map<String, dynamic> j) => CatalogRelation(
        moduleId: (j['module_id'] ?? '').toString(),
        businessTypeValue: (j['business_type_value'] ?? '').toString(),
        relationLevel: (j['relation_level'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'module_id': moduleId,
        'business_type_value': businessTypeValue,
        'relation_level': relationLevel,
      };
}

class CatalogOverride {
  final String moduleId;
  final String forcedState; // active | inactive

  const CatalogOverride({required this.moduleId, required this.forcedState});

  factory CatalogOverride.fromJson(Map<String, dynamic> j) => CatalogOverride(
        moduleId: (j['module_id'] ?? '').toString(),
        forcedState: (j['forced_state'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() =>
      {'module_id': moduleId, 'forced_state': forcedState};
}

/// Catálogo completo tal como lo entrega el backend (+ version/etag).
class Catalog {
  final List<CatalogModule> modules;
  final List<CatalogTypeEntry> types;
  final List<CatalogRelation> relations;
  final List<CatalogOverride> overrides;
  final String version;

  const Catalog({
    required this.modules,
    required this.types,
    required this.relations,
    required this.overrides,
    required this.version,
  });

  static List<T> _list<T>(dynamic raw, T Function(Map<String, dynamic>) f) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => f(e.cast<String, dynamic>()))
        .toList();
  }

  factory Catalog.fromJson(Map<String, dynamic> j) => Catalog(
        modules: _list(j['modules'], CatalogModule.fromJson),
        types: _list(j['types'], CatalogTypeEntry.fromJson),
        relations: _list(j['relations'], CatalogRelation.fromJson),
        overrides: _list(j['overrides'], CatalogOverride.fromJson),
        version: (j['version'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'modules': modules.map((m) => m.toJson()).toList(),
        'types': types.map((t) => t.toJson()).toList(),
        'relations': relations.map((r) => r.toJson()).toList(),
        'overrides': overrides.map((o) => o.toJson()).toList(),
        'version': version,
      };

  bool get isEmpty => modules.isEmpty && types.isEmpty;
}
