# Instant Messenger

Instant Messenger is a modern, cross-platform real-time messaging application built with Flutter, designed for performance, offline-first reliability, and a responsive messaging experience.

---

## Features

### Core Messaging & Real-Time
- **Phone Authentication:** SMS OTP phone login powered by Supabase Auth.
- **Real-Time One-to-One Messaging:** Low-latency real-time chat powered by Supabase Realtime with offline-first synchronization.
- **Monotonic Delivery States:** Forward-only delivery progression (`sending (0) → sent (1) → delivered (2) → read (3)`).
- **Optimistic UI:** Messages appear in the conversation thread immediately while the outbox manages background delivery.
- **Offline-First Outbox:** Outbox daemon handles offline queuing, automatic retries with exponential backoff, and idempotent submission (`SQLSTATE 23505`).
- **Presence & Typing:** Real-time online/offline presence indicators and typing status.
- **Media Messaging:** Compressed images, video thumbnails, voice notes, and Supabase Storage integration with background upload support via Workmanager.

### Push Notifications
- **Dual-Stack Notification Architecture:** Firebase Cloud Messaging (FCM HTTP v1) primary with OneSignal fallback.
- **Duplicate Prevention:** Server-side device partitioning ensures recipient devices receive only one notification per message.
- **Foreground In-App Suppression:** Notifications for the active conversation thread are suppressed while the user is inside the chat screen.
- **Notification Tap Navigation:** Cold-start and warm-start notification taps route directly to the corresponding chat.

---

## Technology Stack

- **Frontend Framework:** Flutter (Dart 3.x)
- **State Management:** Riverpod 3.4.3 (`flutter_riverpod`) — Modern `Notifier<T>` exclusively (Zero legacy APIs)
- **Routing:** GoRouter (`go_router`) with declarative state-driven routing
- **Local Persistence:** Hive 2.x (`hive: ^2.2.3`, `hive_flutter: ^1.1.0`) with multi-account isolation (`messages_<uid>`, `chats_<uid>`, `outbox_<uid>`, `sync_cursors_<uid>`)
- **Backend:** Supabase (PostgreSQL, Auth, Realtime, Storage, Edge Functions)
- **Push Gateways:** Google Firebase Cloud Messaging (FCM HTTP v1) and OneSignal

---

## Architecture

The project follows a **Feature-First Clean Architecture** standard:

```text
lib/
├── app/          # Composition root, GoRouter definition, app bootstrap, themes
├── core/         # Cross-cutting infrastructure (Hive persistence, network, outbox daemon, sync)
├── features/     # Feature-first domains (auth, chats, messaging, contacts, profile, media, notifications, settings, calls)
└── shared/       # Shared presentation widgets and utilities
```

For complete architectural details, see [architecture_design.md](architecture_design.md) and [architecture_migration_roadmap.md](architecture_migration_roadmap.md). Canonical development rules are maintained in [AGENTS.md](AGENTS.md).

---

## Getting Started

### Prerequisites
- Flutter SDK 3.x
- Dart SDK 3.x
- Android SDK (API 34+)

### Installation
```bash
flutter pub get
```

### Run Static Analysis
```bash
flutter analyze --no-fatal-infos
```

### Run Tests
```bash
flutter test
```

### Build Debug APK
```bash
flutter build apk --debug
```
