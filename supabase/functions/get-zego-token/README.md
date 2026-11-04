# Supabase Edge Function: `get-zego-token`

Secure, server-side ZEGOCLOUD Token04 generation endpoint for Instant Messenger audio and video calling.

---

## 1. Required ZEGOCLOUD Configuration & Secrets

The Edge Function requires two server-side environment secrets:

| Secret Name | Type | Description |
| :--- | :--- | :--- |
| `ZEGO_APP_ID` | Number | Numeric App ID obtained from the [ZEGOCLOUD Admin Console](https://console.zegocloud.com/). |
| `ZEGO_SERVER_SECRET` | String (32 bytes) | 32-character hex/ASCII Server Secret key corresponding to your `ZEGO_APP_ID`. |

> [!CAUTION]
> **Zero Privileged Secrets in Client**: In compliance with Project Rule F, never place `ZEGO_SERVER_SECRET` into client `.env` files, Dart source code, or Android resources. It must remain strictly in Supabase server-side environment secrets.

---

## 2. Setting Secrets in Supabase

### Via Supabase CLI:
```bash
supabase secrets set ZEGO_APP_ID="<your_app_id>" ZEGO_SERVER_SECRET="<your_32_byte_server_secret>"
```

### Via Supabase Dashboard:
1. Navigate to your Supabase Project Dashboard.
2. Go to **Project Settings** -> **Edge Functions** -> **Secrets**.
3. Add `ZEGO_APP_ID` and `ZEGO_SERVER_SECRET`.

---

## 3. Running & Testing the Edge Function Locally

To test the function locally using the Supabase CLI:

```bash
# Start local Supabase containers (if not running)
supabase start

# Serve Edge Functions with local environment secrets
supabase functions serve get-zego-token --env-file supabase/.env.local
```

Where `supabase/.env.local` contains:
```env
ZEGO_APP_ID="123456789"
ZEGO_SERVER_SECRET="0123456789abcdef0123456789abcdef"
```

---

## 4. Request & Response Specification

### Request
- **Endpoint**: `POST /functions/v1/get-zego-token`
- **Headers**:
  ```http
  Authorization: Bearer <SUPABASE_USER_JWT>
  Content-Type: application/json
  ```
- **Body** (optional):
  ```json
  {
    "room_id": "call-uuid-room-123",
    "effective_time_in_seconds": 3600,
    "call_type": "video"
  }
  ```

| Field | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `room_id` | String | No | Optional room/channel restriction (max 128 chars). |
| `effective_time_in_seconds` | Number | No | Validity duration in seconds (min 60, max 86400, default 3600). |
| `call_type` | String | No | `"audio"` or `"video"`. |

> [!IMPORTANT]
> Any `user_id` passed in the request body is intentionally **ignored**. The user identity is derived exclusively from the verified Supabase Auth JWT (`user.id`) to prevent caller impersonation.

### Success Response (`200 OK`)
```json
{
  "token": "04AAAAAGrijdkAEGE5N3JiMnJvZTZrc3Joc2MAcEWEi3t0...",
  "app_id": 123456789,
  "user_id": "e2a4b880-9b36-4d22-9029-2182c1e7a5c1",
  "expires_at": 1793232345
}
```

### Error Responses
- `401 Unauthorized`: Missing or invalid Bearer token.
- `400 Bad Request`: Malformed JSON or out-of-bounds parameters.
- `405 Method Not Allowed`: HTTP method is not POST or OPTIONS.
- `500 Internal Server Error`: Missing server secrets or unexpected server failure (no internal stack traces leaked).

---

## 5. Authenticated User Identity Mapping

- **Supabase Identity**: Canonical RFC-4122 UUID string (e.g. `e2a4b880-9b36-4d22-9029-2182c1e7a5c1`).
- **ZEGOCLOUD Identity**: ZEGOCLOUD allows user IDs up to 64 bytes containing alphanumeric characters, hyphens, and underscores. The Supabase `user.id` maps **1:1 directly** as the ZEGOCLOUD `userID`.
- This ensures consistency between chat contacts, Supabase profile records, and in-call participant IDs.

---

## 6. Token Expiration & Client Refresh Requirements

1. **Token Lifetime**: The default token lifetime is 3600 seconds (1 hour).
2. **Expiration Tracking**: The client checks `tokenResponse.isExpired` before initiating calls.
3. **In-Call Refresh**: When a call exceeds 1 hour or the token nears expiration, the future Flutter calling service will invoke `CallsRepository.getZegoToken()` and provide the refreshed token to the ZEGOCLOUD SDK via `ZegoUIKitPrebuiltCallInvitationService().renewToken()`.

---

## 7. AppSign vs Token Authentication

| Feature | AppSign (Development Mode) | Token04 (Production Mode) |
| :--- | :--- | :--- |
| **Secret Location** | Hardcoded inside Flutter application code. | Kept strictly on the backend (Supabase Edge Function). |
| **Vulnerability** | Extractable by reverse-engineering the APK. | Impossible to steal without server compromise. |
| **Privileges** | Grants unconditional access to the App ID. | Granularly scopes user identity, room ID, and expiration. |
| **Project Stance** | **Forbidden** by Project Rule F. | **Mandatory** across all phases. |

---

## 8. What Remains Necessary Before Real Calls Can Work (Phases 2-4)

1. **ZEGOCLOUD Project Setup**: Obtain actual `AppID` and `ServerSecret` from the ZEGOCLOUD console and configure them as Supabase secrets.
2. **Phase 2**: Add `zego_uikit_prebuilt_call` to `pubspec.yaml`, wire `CallsRepository.getZegoToken()` into the Flutter app, and replace the placeholder `CallScreen`.
3. **Phase 3**: Configure Firebase Cloud Messaging (FCM) credentials in the ZEGOCLOUD console with a `resourceID` to enable offline/background incoming call invitations.
4. **Phase 4**: Replace the dummy `CallsTab` with real interactive call history powered by `CallRecord`.
