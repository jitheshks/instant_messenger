import 'package:flutter/material.dart';

/// Reusable phone number form field with dial code prefix and country-aware format validation.
class PhoneNumberField extends StatelessWidget {
  final String dialCode;
  final String countryCode;
  final ValueChanged<String>? onChanged;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  const PhoneNumberField({
    super.key,
    required this.dialCode,
    required this.countryCode,
    this.onChanged,
    this.controller,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Text(
            dialCode,
            style: textTheme.titleMedium,
          ),
        ),
        Expanded(
          child: TextFormField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              hintText: 'Phone number',
            ),
            validator: (v) {
              final t = (v ?? '').replaceAll(RegExp(r'\s+'), '');
              if (t.isEmpty) return 'Enter phone number';

              final iso = countryCode.toUpperCase();
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
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
