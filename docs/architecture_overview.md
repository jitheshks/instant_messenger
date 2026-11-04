# Instant Messenger — Architecture Overview

## 1. High-Level Architecture

The application adopts a concentric Model-View-Controller (MVC) architecture with clean boundary separation across Presentation, Domain, and Data layers:

```
[Presentation Layer] (Widgets, Screens, Theme)
        │
        ▼
[Controller / State Layer] (Riverpod 3.x Notifier & AsyncNotifier)
        │
        ▼
[Domain Layer] (Pure Dart Models, Entity Contracts, Value Objects)
        ▲
        │
[Data Layer] (Repositories, Hive Local Stores, Supabase APIs, OneSignal SDK)
```

---

## 2. Layer Responsibilities

### Presentation Layer (`lib/features/*/presentation/` & `lib/shared/`)
- Pure Flutter UI components, widgets, and screens.
- Zero direct database queries or raw HTTP calls.
- Listens to Riverpod state notifiers using `ConsumerWidget` or `ConsumerStatefulWidget`.
- Modular UI components (e.g. `ProfileAvatarSelector`, `ReplyComposerPreview`, `ChatBubbleReply`, `ChatSelectionActions`).

### Controller / Notifier Layer (`lib/features/*/presentation/controllers/` & `providers/`)
- Manages user interaction workflows, asynchronous states, loading indicators, and error messages.
- Coordinates business logic between UI and repositories.
- Keeps UI reactive without triggering full-screen re-renders.

### Domain Layer (`lib/features/*/domain/`)
- Encapsulates pure business entities and models (`ChatMessage`, `UserProfile`, `ChatSummary`, `ContactListEntry`).
- Free from Flutter widget imports, Riverpod dependencies, or Supabase SDK classes.
- Immutable data structures with serialization/deserialization helpers (`fromMap`, `toMap`, `copyWith`).

### Data Layer (`lib/features/*/data/` & `lib/core/persistence/`)
- Repositories (`MessagesRepository`, `ChatsRepository`, `ContactRepository`) mediating between local persistence and remote backends.
- Account-isolated Hive boxes (`messages_<uid>`, `chats_<uid>`, `outbox_<uid>`, `sync_cursors_<uid>`) ensuring zero cross-account cache leakage.
- Network and external SDK adapters (`OneSignalService`, `FcmService`, `SupabaseClient`).

---

## 3. Offline-First Sync Architecture

The offline-first synchronization engine ensures messages are never lost during intermittent connectivity:

1. **Immediate Optimistic Persistence:**
   Messages are saved into local Hive box with `deliveryState: DeliveryState.sending` (0) and shown immediately in the chat timeline.
2. **Outbox Mutation Queuing:**
   `OutboxService` queues mutations with exponential backoff and crash recovery.
3. **OutboxDaemon Worker:**
   Monitors connectivity and submits pending mutations to Supabase PostgreSQL idempotently (handling `SQLSTATE 23505`).
4. **Reconciliation Engine:**
   `ReconciliationService` deduplicates Realtime incoming events against local optimistic cache and advances delivery states monotonically (`sending -> sent -> delivered -> read`).

---

## 4. Diagnostics & Error Handling

- **Logging Abstraction:**
  [`AppLogger`](file:///home/blackhat/Documents/instant_messenger/lib/core/logging/app_logger.dart) provides structured diagnostic logs (`debug`, `info`, `warning`, `error`) with automated credential sanitization.
- **Error Mapping:**
  [`AppErrorMapper`](file:///home/blackhat/Documents/instant_messenger/lib/core/errors/app_error_mapper.dart) safely maps PostgreSQL RLS violations, unique constraint failures, socket timeouts, and network disconnects to user-facing strings without leaking database internals.
