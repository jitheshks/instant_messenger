// lib/features/contacts/presentation/providers/contacts_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/features/contacts/data/contact_repository.dart';
import 'package:instant_messenger/features/contacts/presentation/controllers/contacts_data_notifier.dart';

final contactsRepositoryProvider = Provider<ContactsRepository>((ref) {
  return ContactsRepository();
});

final contactsDataControllerProvider =
    NotifierProvider<ContactsDataNotifier, ContactsDataState>(
      ContactsDataNotifier.new,
    );

final contactsDataNotifierProvider = contactsDataControllerProvider;
