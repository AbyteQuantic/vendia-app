// Spec: specs/008-planes-suscripcion-epayco/spec.md
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/models/subscription.dart';

/// Unit tests for the Feature 008 subscription models. The headline
/// invariant (lesson of F1): models READ the `id` from the backend
/// payload — they never invent it.
void main() {
  group('SubscriptionPlan.fromJson', () {
    test('reads id from the backend payload, not a generated value', () {
      final plan = SubscriptionPlan.fromJson(const {
        'id': 'pro',
        'name': 'Pro',
        'description': 'Todas las herramientas',
        'prices': [
          {'interval': 'mensual', 'amount': 29900, 'currency': 'COP'},
          {'interval': 'anual', 'amount': 299000, 'currency': 'COP'},
        ],
        'features': ['Reportes', 'Fiar a clientes'],
      });

      expect(plan.id, equals('pro'));
      expect(plan.name, equals('Pro'));
      expect(plan.prices, hasLength(2));
      expect(plan.priceFor('mensual')?.amount, equals(29900));
      expect(plan.priceFor('anual')?.amount, equals(299000));
      expect(plan.isFree, isFalse);
      expect(plan.features, contains('Reportes'));
    });

    test('Gratis plan with a single zero-cost price is reported as free', () {
      final plan = SubscriptionPlan.fromJson(const {
        'id': 'gratis',
        'name': 'Gratis',
        'prices': [
          {'interval': 'mensual', 'amount': 0},
        ],
      });

      expect(plan.id, equals('gratis'));
      expect(plan.isFree, isTrue);
    });

    test('falls back to flat monthly/yearly fields when prices is absent',
        () {
      final plan = SubscriptionPlan.fromJson(const {
        'id': 'pro',
        'name': 'Pro',
        'monthly_amount': 29900,
        'yearly_amount': 299000,
      });

      expect(plan.priceFor('mensual')?.amount, equals(29900));
      expect(plan.priceFor('anual')?.amount, equals(299000));
    });

    test('priceFor returns null for an interval the plan does not offer',
        () {
      final plan = SubscriptionPlan.fromJson(const {
        'id': 'pro',
        'name': 'Pro',
        'prices': [
          {'interval': 'mensual', 'amount': 29900},
        ],
      });

      expect(plan.priceFor('anual'), isNull);
    });
  });

  group('SubscriptionStatus.fromJson', () {
    test('parses an active Pro subscription', () {
      final status = SubscriptionStatus.fromJson(const {
        'status': 'PRO_ACTIVE',
        'plan': 'pro',
        'interval': 'mensual',
        'expires_at': '2026-06-17T00:00:00Z',
      });

      expect(status.status, equals('PRO_ACTIVE'));
      expect(status.plan, equals('pro'));
      expect(status.interval, equals('mensual'));
      expect(status.expiresAt, isNotNull);
      expect(status.isPremium, isTrue);
      expect(status.isTrial, isFalse);
    });

    test('accepts current_period_end as an alias for expires_at', () {
      final status = SubscriptionStatus.fromJson(const {
        'status': 'PRO_ACTIVE',
        'plan': 'pro',
        'current_period_end': '2026-12-31T00:00:00Z',
      });

      expect(status.expiresAt, isNotNull);
    });

    test('a trial counts as premium and exposes days remaining', () {
      final status = SubscriptionStatus.fromJson(const {
        'status': 'TRIAL',
        'plan': 'pro',
        'trial_days_remaining': 9,
      });

      expect(status.isPremium, isTrue);
      expect(status.isTrial, isTrue);
      expect(status.trialDaysRemaining, equals(9));
    });

    test('FREE status is not premium', () {
      final status = SubscriptionStatus.fromJson(const {
        'status': 'FREE',
        'plan': 'gratis',
      });

      expect(status.isPremium, isFalse);
    });

    test('defaults to FREE when status is missing', () {
      final status = SubscriptionStatus.fromJson(const {});
      expect(status.status, equals('FREE'));
      expect(status.isPremium, isFalse);
    });
  });

  group('CheckoutSession.fromJson', () {
    test('parses the ePayco checkout payload with a direct URL', () {
      final session = CheckoutSession.fromJson(const {
        'reference': 'VENDIA-PRO-001',
        'checkout_url': 'https://checkout.epayco.co/abc',
        'amount': 29900,
        'description': 'VendIA Pro mensual',
        'plan': 'pro',
        'interval': 'mensual',
      });

      expect(session.reference, equals('VENDIA-PRO-001'));
      expect(session.checkoutUrl, equals('https://checkout.epayco.co/abc'));
      expect(session.hasUrl, isTrue);
      expect(session.amount, equals(29900));
      expect(session.plan, equals('pro'));
    });

    test('hasUrl is false when the backend sends no URL', () {
      final session = CheckoutSession.fromJson(const {
        'reference': 'VENDIA-PRO-002',
        'amount': 299000,
        'description': 'VendIA Pro anual',
        'plan': 'pro',
      });

      expect(session.hasUrl, isFalse);
    });

    test('accepts ref / url aliases', () {
      final session = CheckoutSession.fromJson(const {
        'ref': 'R-123',
        'url': 'https://checkout.epayco.co/x',
        'amount': 29900,
        'plan': 'pro',
      });

      expect(session.reference, equals('R-123'));
      expect(session.checkoutUrl, equals('https://checkout.epayco.co/x'));
    });
  });
}
