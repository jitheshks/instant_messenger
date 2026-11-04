import 'package:flutter/foundation.dart';

/// Decisions made by [ChatPreviewOrderingPolicy] when evaluating an incoming or
/// candidate message against an established conversation preview.
enum CandidateAction {
  /// The candidate message is strictly newer and should replace the conversation preview.
  replacePreview,

  /// The candidate message matches the established preview message;
  /// only its delivery status should be updated monotonically.
  updateStatusOnly,

  /// The candidate message is older, or is a distinct message sharing an identical
  /// timestamp. Under the Stage 2C Conservative Tie Policy, the established preview is preserved.
  ignoreCandidate,
}

/// Centralized ordering and tie-breaking policy for conversation list previews.
///
/// Implements the Stage 2C Conservative Tie Policy:
/// 1. If candidate timestamp is strictly newer, accept the candidate ([CandidateAction.replacePreview]).
/// 2. If candidate timestamp is strictly older, preserve the existing preview ([CandidateAction.ignoreCandidate]).
/// 3. If timestamps are identical:
///    - If message IDs match, allow monotonic delivery-status progression ([CandidateAction.updateStatusOnly]).
///    - If message IDs differ, preserve the established preview ([CandidateAction.ignoreCandidate]).
/// 4. Never use pseudo-random client UUID comparisons as a substitute for chronological ordering.
@immutable
class ChatPreviewOrderingPolicy {
  const ChatPreviewOrderingPolicy._();

  /// Evaluates whether a candidate message should replace or update an established preview.
  static CandidateAction evaluate({
    required DateTime candidateTime,
    required String? candidateMessageId,
    required DateTime existingTime,
    required String? existingMessageId,
  }) {
    if (candidateTime.isAfter(existingTime)) {
      return CandidateAction.replacePreview;
    }

    if (candidateTime.isBefore(existingTime)) {
      return CandidateAction.ignoreCandidate;
    }

    // Timestamps are identical (isAtSameMomentAs)
    if (candidateMessageId != null &&
        existingMessageId != null &&
        candidateMessageId.isNotEmpty &&
        candidateMessageId == existingMessageId) {
      return CandidateAction.updateStatusOnly;
    }

    // Distinct messages with identical timestamps:
    // Conservative tie policy preserves the established preview without relying on random UUID characters.
    return CandidateAction.ignoreCandidate;
  }
}
