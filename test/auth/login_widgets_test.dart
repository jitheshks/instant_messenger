import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/auth/presentation/widgets/country_picker_tile.dart';
import 'package:instant_messenger/features/auth/presentation/widgets/phone_number_field.dart';

void main() {
  group('Auth Extracted Widgets Tests', () {
    testWidgets('CountryPickerTile renders emoji flag and country name', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CountryPickerTile(
              flagEmoji: '🇮🇳',
              countryName: 'India',
              onSelect: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('🇮🇳'), findsOneWidget);
      expect(find.text('India'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
    });

    testWidgets('PhoneNumberField renders dial code and validates phone input', (
      tester,
    ) async {
      final formKey = GlobalKey<FormState>();
      String changedPhone = '';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Form(
              key: formKey,
              child: PhoneNumberField(
                dialCode: '+91',
                countryCode: 'IN',
                onChanged: (v) => changedPhone = v,
              ),
            ),
          ),
        ),
      );

      expect(find.text('+91'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '9876543210');
      expect(changedPhone, '9876543210');

      final valid = formKey.currentState?.validate();
      expect(valid, isTrue);
    });

    testWidgets('PhoneNumberField rejects invalid Indian number', (
      tester,
    ) async {
      final formKey = GlobalKey<FormState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Form(
              key: formKey,
              child: PhoneNumberField(
                dialCode: '+91',
                countryCode: 'IN',
              ),
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextFormField), '12345');
      final valid = formKey.currentState?.validate();
      expect(valid, isFalse);

      await tester.pump();
      expect(find.text('Enter 10‑digit Indian number'), findsOneWidget);
    });
  });
}
