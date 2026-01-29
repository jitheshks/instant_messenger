import 'package:flutter/material.dart';
import 'package:country_picker/country_picker.dart';
import 'package:instant_messenger/controller/login_screen_controller.dart';
import 'package:provider/provider.dart';

class LoginScreen extends StatelessWidget {
  LoginScreen({super.key});

  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    debugPrint('🔵 BUILD → LoginScreen');

    final c = context.watch<LoginController>();
    final cs = Theme.of(context).colorScheme;
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

                // Country picker trigger (bottom sheet dialog)
                // Picker row WITHOUT dial code in trailing
                // Country picker trigger (bottom sheet dialog) — no dial code here
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: cs.outlineVariant),
                  ),
                  tileColor: Theme.of(context).colorScheme.surface,
                  leading: Text(
                    c.flagEmoji ?? '🇮🇳',
                    style: const TextStyle(fontSize: 24),
                  ),
                  title: Text(
                    c.countryName ?? 'India',
                    style: textTheme.bodyLarge,
                  ),
                  trailing: const Icon(Icons.arrow_drop_down),
                  onTap: () {
                    showCountryPicker(
                      context: context, // required [1]
                      showPhoneCode: true, // optional [1]
                      favorite: const [
                        'IN',
                      ], // pin India (list still full) [11]
                      countryListTheme: CountryListThemeData(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                        bottomSheetHeight: 500,
                        inputDecoration: const InputDecoration(
                          labelText: 'Search',
                          hintText: 'Start typing to search',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      onSelect: (Country country) {
                        // required [1]
                        context.read<LoginController>().onCountryPicked(
                          name: country.name,
                          countryCode: country.countryCode, // e.g. 'IN'
                          dialCode: '+${country.phoneCode}', // e.g. '+91'
                          flagEmoji: country.flagEmoji, // e.g. 🇮🇳
                        );
                      },
                    );
                  },
                ),

                const SizedBox(height: 16),

                // Dial code + phone input row (keep prefix here)
                Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Text(
                        c.dialCode ?? '+91',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Expanded(
                      child: TextFormField(
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          hintText: 'Phone number',
                        ),
                        validator: (v) {
                          final t = (v ?? '').replaceAll(RegExp(r'\s+'), '');
                          if (t.isEmpty) return 'Enter phone number';

                          final iso = c.countryCode.toUpperCase();
                          final isIndia = iso == 'IN';
                          final valid = isIndia
                              ? RegExp(r'^[6-9][0-9]{9}$').hasMatch(t)
                              : RegExp(r'^[0-9]{5,15}$').hasMatch(t);

                          return valid
                              ? null
                              : (isIndia
                                    ? 'Enter 10‑digit Indian number'
                                    : 'Enter valid number');
                        },
                        onChanged: context
                            .read<LoginController>()
                            .onPhoneChanged,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

              

                const Spacer(),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: c.loading
                        ? null
                        : () async {
                            final ok =
                                _formKey.currentState?.validate() ?? false;
                            if (!ok) return;
                            _formKey.currentState?.save();
                            await context.read<LoginController>().onNext(
                              context,
                            );
                          },
                    child: c.loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Next'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
