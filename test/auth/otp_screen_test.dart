import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/auth/presentation/screens/otp_screen.dart';
import 'package:instant_messenger/features/auth/presentation/widgets/otp_pin_input.dart';
import 'package:pinput/pinput.dart';

void main() {
  group('OtpScreen & OtpPinInput Widget Tests (Pinput ^7.0.0 Compatibility)', () {
    testWidgets(
      'OtpScreen renders OtpPinInput and Pinput within Scaffold cleanly without throwing',
      (tester) async {
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: OtpScreen(),
            ),
          ),
        );

        // Verify that OtpScreen builds cleanly
        expect(find.byType(OtpScreen), findsOneWidget);
        expect(find.byType(Scaffold), findsOneWidget);
        expect(find.byType(OtpPinInput), findsOneWidget);
        expect(find.byType(Pinput), findsOneWidget);
        expect(find.text('Verify your number'), findsOneWidget);
        expect(find.text('We have sent a 6‑digit code to'), findsOneWidget);
        expect(find.byType(FilledButton), findsOneWidget);
        expect(find.text('Next'), findsOneWidget);

        // Verify entering digits into Pinput
        await tester.enterText(find.byType(Pinput), '123456');
        await tester.pump();
        expect(find.text('123456'), findsOneWidget);
      },
    );

    testWidgets(
      'OtpPinInput standalone reusable widget handles input and callbacks with pinput 7.0.0',
      (tester) async {
        String latestValue = '';
        String completedValue = '';

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: OtpPinInput(
                  length: 6,
                  onChanged: (v) => latestValue = v,
                  onCompleted: (v) => completedValue = v,
                ),
              ),
            ),
          ),
        );

        expect(find.byType(OtpPinInput), findsOneWidget);
        expect(find.byType(Pinput), findsOneWidget);

        // Enter partial text
        await tester.enterText(find.byType(Pinput), '123');
        await tester.pump();
        expect(latestValue, equals('123'));
        expect(completedValue, isEmpty);

        // Complete 6 digits
        await tester.enterText(find.byType(Pinput), '123456');
        await tester.pump();
        expect(latestValue, equals('123456'));
        expect(completedValue, equals('123456'));
      },
    );
  });
}
