/// Decision matrix for the Growth Radar — which sales count toward
/// the merchant's annual digital-revenue tally.
///
/// Conservative bucket: returns false on every payment method that
/// is either physical cash, an unpaid credit, or an unbreakable
/// 'multi' aggregate. Anything else (transfer, card, named wallet
/// like nequi/daviplata, future tenant-custom digital wallets) is
/// digital.
bool isDigitalPaymentMethod(String? raw) {
  if (raw == null) return false;
  final m = raw.trim().toLowerCase();
  if (m.isEmpty) return false;
  // Physical cash — excluded by DIAN business rule.
  if (m == 'cash' || m == 'efectivo') return false;
  // Unpaid credit (Fiar). Counts only when settled — and the
  // settlement appears as its own LocalSale with the abono's
  // method, never as the original credit row.
  if (m == 'credit' || m == 'fiado') return false;
  // Multi-method aggregate from a closed mesa with mixed abonos.
  // We don't store the breakdown today; counting it would either
  // overcount (if it was 100% cash) or undercount (if it was
  // 100% digital). Excluding it is the conservative call —
  // future PR will store the breakdown and we'll revisit.
  if (m == 'multi') return false;
  return true;
}
