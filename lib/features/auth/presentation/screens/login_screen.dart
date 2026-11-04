import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/features/auth/presentation/providers/auth_providers.dart';
import 'package:instant_messenger/features/auth/presentation/widgets/country_picker_tile.dart';
import 'package:instant_messenger/features/auth/presentation/widgets/phone_number_field.dart';
import 'package:instant_messenger/shared/widgets/buttons/primary_action_button.dart';

class LoginScreen extends ConsumerWidget {
  LoginScreen({super.key});

  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('🔵 BUILD → LoginScreen');

    final c = ref.watch(loginControllerProvider);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Enter your phone number')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Text(
                  'Instant Messenger will need to verify your phone number. Carrier charges may apply.',
                  style: textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Country picker trigger
                CountryPickerTile(
                  flagEmoji: c.flagEmoji,
                  countryName: c.countryName,
                  onSelect: (country) {
                    ref.read(loginControllerProvider.notifier).onCountryPicked(
                          name: country.name,
                          countryCode: country.countryCode,
                          dialCode: '+${country.phoneCode}',
                          flagEmoji: country.flagEmoji,
                        );
                  },
                ),

                const SizedBox(height: 16),

                // Dial code + phone input row
                PhoneNumberField(
                  dialCode: c.dialCode,
                  countryCode: c.countryCode,
                  onChanged: ref
                      .read(loginControllerProvider.notifier)
                      .onPhoneChanged,
                ),

                const Spacer(),

                PrimaryActionButton(
                  label: 'Next',
                  isLoading: c.loading,
                  onPressed: () async {
                    final ok = _formKey.currentState?.validate() ?? false;
                    if (!ok) return;
                    _formKey.currentState?.save();
                    await ref
                        .read(loginControllerProvider.notifier)
                        .onNext(context);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
