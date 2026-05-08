/// Supabase project credentials shared across upload flows. The anon
/// key is **public by design** (it carries only `role=anon` and is
/// scoped per-project) and is safe to ship in the Flutter binary.
/// Server-side guarantees protect the bucket:
///   * RLS restricts inserts to the `payment_receipts` bucket.
///   * Bucket-level `file_size_limit` (5 MB) + `allowed_mime_types`
///     keep abuse contained.
///   * `pg_cron` purges blobs older than 8 days, capping our exposure.
///
/// Do NOT replace this with the service-role key — that one IS
/// secret and would bypass every guard above.
library supabase_config;

const String supabaseUrl = 'https://zwoqdbkybopctymftknr.supabase.co';

const String supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp3b3FkYmt5Ym9wY3R5bWZ0a25yIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3OTUwMTAsImV4cCI6MjA5MDM3MTAxMH0.3TG2SYZiMCyesnc5A2YqJ5X_gI-pVQaoLje3ab1WG7k';

/// Public bucket where the cashier's payment receipts live. The
/// 8-day TTL is enforced by `purge_old_payment_receipts` (pg_cron).
const String supabaseReceiptsBucket = 'payment_receipts';
