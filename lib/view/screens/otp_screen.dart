import 'package:flutter/material.dart';
import 'package:pinput/pinput.dart';
import 'package:provider/provider.dart';
import '../../controller/login_screen_controller.dart';

class OtpScreen extends StatelessWidget {
  const OtpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<LoginController>();
    final cs = Theme.of(context).colorScheme;
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
                child: Pinput(
                  length: 6, // typical OTP length [web:421]
                  defaultPinTheme: PinTheme(
                    width: 48,
                    height: 56,
                    textStyle: textTheme.headlineSmall,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                  ),
                  onChanged: context.read<LoginController>().onOtpChanged,
                  onCompleted: (code) {
                    // Optional: auto-submit; comment out if manual Next is preferred
                    // context.read<LoginController>().submitCode(context, code);
                  },
                ),
              ),

              const SizedBox(height: 16),

              Center(
                child: TextButton(
                  onPressed: c.canResend && !c.loading
                      ? () => context.read<LoginController>().resendCode(context)
                      : null,
                  child: Text(
                    c.canResend
                        ? "Didn't receive code? Resend"
                        : "Resend available in ${c.secondsLeft}s",
                  ),
                ),
              ),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: c.loading
                      ? null
                      : () async {
                          if (c.otpCode.isEmpty || c.otpCode.length < 4) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Enter the code')),
                            );
                            return;
                          }
                          await context.read<LoginController>().submitOtp(context);
                        },
                  child: c.loading
                      ? const SizedBox(
                          height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Next'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
