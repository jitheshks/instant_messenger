import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/features/auth/presentation/providers/auth_providers.dart';
import 'package:instant_messenger/features/auth/presentation/widgets/otp_pin_input.dart';
import 'package:instant_messenger/shared/widgets/buttons/primary_action_button.dart';

class OtpScreen extends ConsumerWidget {
  const OtpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(loginControllerProvider);
    final textTheme = Theme.of(context).textTheme;

    final phoneMasked = c.otp?.e164 ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Verify your number')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                'We have sent a 6‑digit code to',
                style: textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                phoneMasked,
                style: textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              Center(
                child: OtpPinInput(
                  length: 6,
                  onChanged: ref
                      .read(loginControllerProvider.notifier)
                      .onOtpChanged,
                  onCompleted: (code) {
                    // Optional: auto-submit; comment out if manual Next is preferred
                    // ref.read(loginControllerProvider.notifier).submitCode(context, code);
                  },
                ),
              ),

              const SizedBox(height: 16),

              Center(
                child: TextButton(
                  onPressed: c.canResend && !c.loading
                      ? () => ref
                            .read(loginControllerProvider.notifier)
                            .resendCode(context)
                      : null,
                  child: Text(
                    c.canResend
                        ? "Didn't receive code? Resend"
                        : "Resend available in ${c.secondsLeft}s",
                  ),
                ),
              ),

              const Spacer(),

              PrimaryActionButton(
                label: 'Next',
                isLoading: c.loading,
                onPressed: () async {
                  if (c.otpCode.isEmpty || c.otpCode.length < 4) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Enter the code')),
                    );
                    return;
                  }
                  await ref
                      .read(loginControllerProvider.notifier)
                      .submitOtp(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
