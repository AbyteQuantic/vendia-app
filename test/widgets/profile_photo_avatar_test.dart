// Spec: specs/019-foto-perfil-tendero-empleado/spec.md
//
// Tests for `ProfilePhotoAvatar`, the circular profile avatar shown for
// the owner (tendero) and each employee.
//
// Spec 019 / D3, FR-05: the profile photo is rendered as a circular
// avatar. When there is no photo yet, the avatar must fall back to the
// person's initials over a solid background — never an empty hole
// (Constitution Art. I: a screen always reads cleanly).
//
// These tests run in the Dart VM and pin two things:
//   * with a `photoUrl` -> an `Image` (network) is built;
//   * without one      -> the initials placeholder is shown.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/widgets/profile_photo_avatar.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: child))),
    );
  }

  group('ProfilePhotoAvatar — placeholder (Spec 019)', () {
    testWidgets('shows two-letter initials when there is no photo',
        (tester) async {
      await pump(
        tester,
        const ProfilePhotoAvatar(name: 'María López'),
      );

      expect(find.text('ML'), findsOneWidget);
      // No photo -> no Image widget, only the initials placeholder.
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('uses a single initial for a single-word name',
        (tester) async {
      await pump(tester, const ProfilePhotoAvatar(name: 'Pedro'));
      expect(find.text('P'), findsOneWidget);
    });

    testWidgets('falls back to "?" for an empty name', (tester) async {
      await pump(tester, const ProfilePhotoAvatar(name: '   '));
      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('an empty photoUrl still renders the initials placeholder',
        (tester) async {
      await pump(
        tester,
        const ProfilePhotoAvatar(name: 'Ana Ruiz', photoUrl: ''),
      );
      expect(find.text('AR'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });
  });

  group('ProfilePhotoAvatar — photo (Spec 019)', () {
    testWidgets('renders a network Image when a photoUrl is given',
        (tester) async {
      await pump(
        tester,
        const ProfilePhotoAvatar(
          name: 'María López',
          photoUrl: 'https://example.com/perfil.png',
        ),
      );

      // A persisted photo -> an Image widget, clipped to a circle.
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(ClipOval), findsOneWidget);
    });

    testWidgets('the avatar is always clipped into a circle', (tester) async {
      await pump(tester, const ProfilePhotoAvatar(name: 'Pedro Gómez'));
      expect(find.byType(ClipOval), findsOneWidget);
    });
  });
}
