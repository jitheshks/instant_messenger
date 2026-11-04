// lib/features/calls/presentation/widgets/invite_participants_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/features/contacts/presentation/providers/contacts_providers.dart';
import '../providers/calls_providers.dart';

/// Modal sheet for adding members to an active group call.
class InviteParticipantsSheet extends ConsumerStatefulWidget {
  final List<String> currentParticipantIds;

  const InviteParticipantsSheet({
    super.key,
    required this.currentParticipantIds,
  });

  static Future<void> show(BuildContext context, List<String> currentParticipantIds) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C2230),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => InviteParticipantsSheet(currentParticipantIds: currentParticipantIds),
    );
  }

  @override
  ConsumerState<InviteParticipantsSheet> createState() => _InviteParticipantsSheetState();
}

class _InviteParticipantsSheetState extends ConsumerState<InviteParticipantsSheet> {
  final Set<String> _selectedUserIds = {};
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final contactsState = ref.watch(contactsDataControllerProvider);
    final eligibleContacts = contactsState.cachedMatched
        .where((c) => c.uid != null && !widget.currentParticipantIds.contains(c.uid!))
        .toList();

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Add to Call',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (eligibleContacts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'No additional contacts available to invite.',
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.45,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: eligibleContacts.length,
                separatorBuilder: (_, _) => const Divider(color: Colors.white12, height: 1),
                itemBuilder: (context, index) {
                  final contact = eligibleContacts[index];
                  final contactId = contact.uid!;
                  final isSelected = _selectedUserIds.contains(contactId);

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: Colors.blueGrey.shade800,
                      child: Text(
                        contact.displayName.isNotEmpty ? contact.displayName[0].toUpperCase() : '?',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(
                      contact.displayName,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      contact.phoneE164 ?? '',
                      style: const TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                    trailing: Checkbox(
                      value: isSelected,
                      activeColor: Colors.tealAccent.shade400,
                      checkColor: Colors.black,
                      onChanged: (checked) {
                        setState(() {
                          if (checked == true) {
                            _selectedUserIds.add(contactId);
                          } else {
                            _selectedUserIds.remove(contactId);
                          }
                        });
                      },
                    ),
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedUserIds.remove(contactId);
                        } else {
                          _selectedUserIds.add(contactId);
                        }
                      });
                    },
                  );
                },
              ),
            ),

          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: (_selectedUserIds.isEmpty || _isSubmitting)
                ? null
                : () async {
                    setState(() {
                      _isSubmitting = true;
                    });
                    final navigator = Navigator.of(context);
                    final scaffold = ScaffoldMessenger.of(context);
                    final count = _selectedUserIds.length;
                    final ok = await ref
                        .read(callControllerProvider.notifier)
                        .inviteParticipants(_selectedUserIds.toList());

                    if (mounted) {
                      navigator.pop();
                      scaffold.showSnackBar(
                        SnackBar(
                          content: Text(ok
                              ? 'Invited $count participant(s)'
                              : 'Failed to invite participants'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.tealAccent.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : Text(
                    'Invite (${_selectedUserIds.length})',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
    );
  }
}
