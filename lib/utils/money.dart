// Spec: specs/077-compra-inteligente-insumos/spec.md
import 'package:intl/intl.dart';

final NumberFormat _copFormat = NumberFormat('#,###', 'es_CO');

/// Formatea un monto en pesos colombianos con separador de miles:
/// 1700 → "$1.700", 1234567 → "$1.234.567". Sin decimales (COP).
String copMoney(num amount) => '\$${_copFormat.format(amount.round())}';
