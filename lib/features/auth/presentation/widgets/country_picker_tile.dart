import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';

/// Reusable country picker tile displaying flag emoji, country name,
/// and triggering a styled country search bottom sheet.
class CountryPickerTile extends StatelessWidget {
  final String flagEmoji;
  final String countryName;
  final ValueChanged<Country> onSelect;
  final List<String> favoriteCountries;

  const CountryPickerTile({
    super.key,
    required this.flagEmoji,
    required this.countryName,
    required this.onSelect,
    this.favoriteCountries = const ['IN'],
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: cs.outlineVariant),
      ),
      tileColor: cs.surface,
      leading: Text(
        flagEmoji,
        style: const TextStyle(fontSize: 24),
      ),
      title: Text(countryName, style: textTheme.bodyLarge),
      trailing: const Icon(Icons.arrow_drop_down),
      onTap: () {
        showCountryPicker(
          context: context,
          showPhoneCode: true,
          favorite: favoriteCountries,
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
          onSelect: onSelect,
        );
      },
    );
  }
}
