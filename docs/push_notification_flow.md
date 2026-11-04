# Instant Messenger — OneSignal Push Notification Flow

This document details the complete end-to-end push notification lifecycle between the Flutter application, Supabase PostgreSQL backend, Supabase Edge Functions, and OneSignal servers.

---

## 1. End-to-End Lifecycle Architecture

```
[Flutter Client (Device A)]
     │
     │ 1. OneSignal.initialize(appId) & login(uid)
     │ 2. OneSignal.User.pushSubscription.id (RFC-4122 UUID)
     │ 3. supabase.rpc('register_device', ...)
     ▼
[Supabase Database: public.user_devices]
     │
     │ 4. Message sent from Device B to chat
     ▼
[Flutter Client (Device B)]
     │
     │ 5. supabase.functions.invoke('send-push', body: {chat_id, message_id})
     ▼
[Supabase Edge Gateway (JWT Validation)]
     │
     ▼
[Supabase Edge Function: send-push]
     │ 6. Verify caller JWT via userClient.auth.getUser()
     │ 7. Enforce public.check_push_rate_limit(p_user_id) RPC
     │ 8. Verify caller membership in chat_members
     │ 9. Verify message authorship in messages
     │ 10. Derive notification preview & sender name from database
     │ 11. Query recipient subscription IDs from user_devices
     │ 12. Filter out raw FCM tokens, keeping only valid OneSignal UUIDs
     │ 13. POST to https://api.onesignal.com/notifications with Key <REST_KEY>
     ▼
[OneSignal REST API & FCM Delivery Transport]
     │
     ▼
[Android Notification Shade (Device A)]
     │
     │ 14. Foreground suppression if in active chat
     │ 15. Notification tap triggers GoRouter navigation to /chats/chat/:chatId
     │ 16. supabase.rpc('promote_message_status', p_new_status: 2) marks delivered
```

---

## 2. Server-Side Edge Function Security Model

The `send-push` Edge Function (`supabase/functions/send-push/index.ts`) enforces strict security controls:

1. **Authentication:**
   Enforces bearer JWT validation via `createClient(supabaseUrl, supabaseAnonKey).auth.getUser()`. Unauthenticated requests receive HTTP 401.
2. **Atomic Sliding-Window Rate Limiter:**
   Executes `public.check_push_rate_limit(p_user_id)` via service role. Rejects callers exceeding 30 requests per 60 seconds with HTTP 429 and `Retry-After`. If database rate limiter is unavailable, the function fails closed with HTTP 503.
3. **Conversation Membership & Authorship:**
   Confirms the caller is an active member in `chat_members` and that the specified `message_id` was authored by `callerId`. Unauthorized callers receive HTTP 403.
4. **Authoritative Database Content Derivation:**
   Notification preview and sender display name are queried directly from `messages` and `profiles` records. Client-supplied titles or previews are completely ignored, eliminating notification spoofing.
5. **Fail-Closed Provider Communication:**
   Bounded by an explicit 8-second timeout (`AbortSignal.timeout(8000)`). Times out with HTTP 504. OneSignal rejections return HTTP 502 with sanitized codes, never leaking server secrets or stack traces.

---

## 3. Remote Secrets Configuration

The Edge Function requires the following environment variables:

| Variable Name | Managed By | Description |
|---|---|---|
| `SUPABASE_URL` | Supabase Runtime | Automatically provided by Edge Runtime |
| `SUPABASE_ANON_KEY` | Supabase Runtime | Automatically provided by Edge Runtime |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase Runtime | Automatically provided by Edge Runtime |
| `ONESIGNAL_APP_ID` | Supabase Vault | Public OneSignal App ID (`70142ddd-32be-40e0-b1ce-97a1b958e3f4`) |
| `ONESIGNAL_REST_KEY` | Supabase Vault | Server-only App REST API key (never stored in Flutter client) |

### Setting Secrets in Supabase Vault:
```bash
supabase secrets set \
  ONESIGNAL_APP_ID="70142ddd-32be-40e0-b1ce-97a1b958e3f4" \
  ONESIGNAL_REST_KEY="<ONESIGNAL_APP_REST_KEY>" \
  --project-ref mpikfmjkblyszjyhyfhz
```

---

## 4. Physical Device Verification Procedure

Once deployed and configured with remote secrets:

1. **Device Registration:**
   Launch the app on Android Device A. Confirm via read-only SQL query that `public.user_devices` contains Device A's OneSignal subscription ID with `subscribed = true`.
2. **Foreground Suppression:**
   Keep Device A in conversation with Account B. Send a message from Account B. In-app chat updates reactively via Realtime; notification shade is suppressed.
3. **Background & Minimized:**
   Minimize app on Device A. Send a message from Account B. Confirm notification appears in notification shade with sender display name and message preview.
4. **Screen Locked (Doze):**
   Lock Device A's screen. Send a message from Account B. Confirm lock-screen alert displays immediately with high priority (`priority: 10`).
5. **App Terminated:**
   Swipe app away from recent apps on Device A. Send message from Account B. Confirm notification arrives reliably via OneSignal FCM transport.
6. **Tap-to-Open Navigation:**
   Tap notification in shade. Confirm app opens directly into conversation with Account B and promotes message status to delivered.
