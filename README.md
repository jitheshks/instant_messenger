📱 Instant Messenger

Instant Messenger is a cross-platform real-time messaging application built with Flutter, focused on performance, reliability, and a WhatsApp-like user experience.
It supports instant text and media messaging with offline handling, background uploads, delivery states, and modern UI/UX.

🚀 Features

Core

📱 Cross-platform Flutter app (Android & iOS)
📞 Phone number–based authentication
💬 Real-time one-to-one messaging
🖼️ Media messaging (images, audio, video, documents)
📌 Message delivery states
(sending → sent → delivered → read)

Realtime UX

🟢 Online / offline presence
✍️ Typing indicators
📅 Date separators (Today / Yesterday / etc.)
🔔 Push notifications via OneSignal

Media & Storage

☁️ Cloudinary for media storage (images, audio, video)
📦 Hive for local cache & offline persistence
📤 Background & resumable media uploads
🔁 Retry & cancel failed uploads
⚡ Optimistic UI (messages appear instantly)

🧱 Architecture

🧠 Clean MVC-inspired architecture (Flutter-adapted)
🎯 Controller-driven business logic
🧩 Modular and reusable widget structure
🔄 Outbox + retry system for reliability

Architecture overview:

Model

Data models, repositories, services, and local cache (Firestore, Cloudinary, Hive)

View

Screens and UI widgets built with Flutter, kept stateless and reactive

Controller

Feature-specific controllers managing state, streams, side effects, and user actions

This separation keeps the codebase scalable, testable, and maintainable.

🛠️ Tech Stack

Frontend

Flutter

Provider (state management)

GoRouter (navigation)

Backend & Services

Firebase Authentication – phone login

Cloud Firestore – real-time chat data

Cloudinary – media storage & delivery

OneSignal – push notifications

Local & Background

Hive – local database & offline cache

WorkManager – background uploads & retries

⚠️ Current Limitations

📞 Audio & video calling UI present
(functionality temporarily disabled)

👥 Group chat support in progress