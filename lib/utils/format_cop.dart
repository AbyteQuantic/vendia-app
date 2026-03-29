/// Formats a COP amount as "$2.500" style string.
String formatCOP(double amount) {
  final int cents = amount.round();
  if (cents == 0) return '\$0';
  final String s = cents.toString();
  final buffer = StringBuffer('\$');
  final start = s.length % 3;
  if (start > 0) buffer.write(s.substring(0, start));
  for (int i = start; i < s.length; i += 3) {
    if (i > 0) buffer.write('.');
    buffer.write(s.substring(i, i + 3));
  }
  return buffer.toString();
}
