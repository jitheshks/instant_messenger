import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  deriveNotificationContent,
  isRateLimited,
  checkRateLimitRpc,
  RateLimitCheckResult,
  handler,
  UUID_REGEX,
  ALLOWED_TYPES,
  MAX_PREVIEW_LENGTH,
  MAX_SENDER_NAME_LENGTH,
  isFcmToken,
  isValidOneSignalSubscriptionId,
} from "./index.ts";

Deno.test("UUID_REGEX validates RFC-4122 UUID strings accurately", () => {
  assertEquals(UUID_REGEX.test("e2a4b880-9b36-4d22-9029-2182c1e7a5c1"), true);
  assertEquals(UUID_REGEX.test("00000000-0000-0000-0000-000000000000"), true);
  assertEquals(UUID_REGEX.test("not-a-uuid"), false);
  assertEquals(UUID_REGEX.test(""), false);
  assertEquals(UUID_REGEX.test("e2a4b880-9b36-4d22-9029-2182c1e7a5c1-extra"), false);
});

Deno.test("ALLOWED_TYPES contains expected message types whitelist", () => {
  assertEquals(ALLOWED_TYPES.has("text"), true);
  assertEquals(ALLOWED_TYPES.has("media"), true);
  assertEquals(ALLOWED_TYPES.has("call"), true);
  assertEquals(ALLOWED_TYPES.has("system"), false);
});

Deno.test("isValidOneSignalSubscriptionId and isFcmToken accurately distinguish providers", () => {
  const validUuid = "70142ddd-32be-40e0-b1ce-97a1b958e3f4";
  const rawFcmToken =
    "fcm_token_sample_abc123_xyz789_long_registration_token_for_device_1234567890_abcdefghij";

  assertEquals(isValidOneSignalSubscriptionId(validUuid), true);
  assertEquals(isFcmToken(validUuid), false);

  assertEquals(isValidOneSignalSubscriptionId(rawFcmToken), false);
  assertEquals(isFcmToken(rawFcmToken), true);

  // Rejects empty, whitespace, colons, and non-UUID strings
  assertEquals(isValidOneSignalSubscriptionId(""), false);
  assertEquals(isValidOneSignalSubscriptionId("   "), false);
  assertEquals(isValidOneSignalSubscriptionId("token:with:colons"), false);
  assertEquals(isValidOneSignalSubscriptionId("player-uuid-001"), false);
});

Deno.test("deriveNotificationContent: Text messages use persisted text truncated to 120 chars", () => {
  const shortMsg = {
    id: "msg-1",
    chat_id: "chat-1",
    sender_id: "user-1",
    type: "text",
    text: "Hello, world!",
  };
  const profile = { display_name: "Alice", phone_e164: "+919876543210" };

  const content = deriveNotificationContent(shortMsg, profile);
  assertEquals(content.preview, "Hello, world!");
  assertEquals(content.type, "text");
  assertEquals(content.senderName, "+919876543210");

  // Long text truncated
  const longMsg = {
    id: "msg-2",
    chat_id: "chat-1",
    sender_id: "user-1",
    type: "text",
    text: "A".repeat(200),
  };
  const longContent = deriveNotificationContent(longMsg, profile);
  assertEquals(longContent.preview.length, MAX_PREVIEW_LENGTH);
  assertEquals(longContent.preview, "A".repeat(MAX_PREVIEW_LENGTH));

  // Empty text falls back to default
  const emptyMsg = {
    id: "msg-3",
    chat_id: "chat-1",
    sender_id: "user-1",
    type: "text",
    text: "   ",
  };
  const emptyContent = deriveNotificationContent(emptyMsg, profile);
  assertEquals(emptyContent.preview, "New message");
});

Deno.test("deriveNotificationContent: Media messages use caption or media kind fallback", () => {
  const profile = { display_name: "Bob" };

  // Media with caption
  const captionMsg = {
    id: "msg-4",
    chat_id: "chat-1",
    sender_id: "user-1",
    type: "media",
    text: "Look at this sunrise!",
    media: { kind: "image" },
  };
  const captionContent = deriveNotificationContent(captionMsg, profile);
  assertEquals(captionContent.preview, "Look at this sunrise!");
  assertEquals(captionContent.type, "media");

  // Image without caption
  const imageMsg = {
    id: "msg-5",
    chat_id: "chat-1",
    sender_id: "user-1",
    type: "media",
    text: "",
    media: { kind: "image" },
  };
  assertEquals(deriveNotificationContent(imageMsg, profile).preview, "📷 Photo");

  // Video without caption
  const videoMsg = {
    id: "msg-6",
    chat_id: "chat-1",
    sender_id: "user-1",
    type: "media",
    text: null,
    media: { kind: "video" },
  };
  assertEquals(deriveNotificationContent(videoMsg, profile).preview, "🎥 Video");

  // Audio without caption
  const audioMsg = {
    id: "msg-7",
    chat_id: "chat-1",
    sender_id: "user-1",
    type: "media",
    text: null,
    media: { kind: "audio" },
  };
  assertEquals(deriveNotificationContent(audioMsg, profile).preview, "🎵 Audio");

  // Generic attachment
  const fileMsg = {
    id: "msg-8",
    chat_id: "chat-1",
    sender_id: "user-1",
    type: "media",
    text: null,
    media: { kind: "document" },
  };
  assertEquals(deriveNotificationContent(fileMsg, profile).preview, "📎 Attachment");
});

Deno.test("deriveNotificationContent: Call messages produce call preview", () => {
  const profile = { display_name: "Charlie" };
  const callMsg = {
    id: "msg-9",
    chat_id: "chat-1",
    sender_id: "user-1",
    type: "call",
  };
  const content = deriveNotificationContent(callMsg, profile);
  assertEquals(content.preview, "📞 Incoming call");
  assertEquals(content.type, "call");
});

Deno.test("deriveNotificationContent: Sender title prefers phone_e164 and falls back without preferring username", () => {
  const msg = {
    id: "msg-10",
    chat_id: "chat-1",
    sender_id: "user-1",
    type: "text",
    text: "Hi",
  };

  // Uses phone_e164 instead of display_name
  assertEquals(
    deriveNotificationContent(msg, { display_name: "AliceUser", phone_e164: "+919876543210" }).senderName,
    "+919876543210"
  );

  // Missing phone falls back to generic "New message" without preferring username
  assertEquals(deriveNotificationContent(msg, null).senderName, "New message");
  assertEquals(deriveNotificationContent(msg, { display_name: "AliceUser", phone_e164: null }).senderName, "New message");
  assertEquals(deriveNotificationContent(msg, { display_name: "AliceUser", phone_e164: "   " }).senderName, "New message");

  // Long phone truncated
  const longPhone = "+91" + "9".repeat(100);
  const content = deriveNotificationContent(msg, { phone_e164: longPhone });
  assertEquals(content.senderName.length, MAX_SENDER_NAME_LENGTH);
});

Deno.test("isRateLimited: Enforces sliding window limit of 30 req / 60s per user", () => {
  const testStore = new Map<string, number[]>();
  const user = "test-user-rate-limit";
  const baseTime = 1000000000;

  // First 30 requests within 60s window are permitted
  for (let i = 0; i < 30; i++) {
    const limited = isRateLimited(user, baseTime + i * 1000, testStore);
    assertEquals(limited, false, `Request ${i} should be permitted`);
  }

  // 31st request within the same 60s window is blocked
  const blocked = isRateLimited(user, baseTime + 35000, testStore);
  assertEquals(blocked, true, "31st request must be rate limited");

  // After 61 seconds from start, older requests slide out and request is permitted
  const reset = isRateLimited(user, baseTime + 61000, testStore);
  assertEquals(reset, false, "Request after window resets must be permitted");
});

Deno.test("handler: Handles CORS preflight with 200 OK and CORS headers", async () => {
  const req = new Request("http://localhost:8000/send-push", {
    method: "OPTIONS",
  });
  const res = await handler(req);
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");
  assertEquals(await res.text(), "ok");
});

Deno.test("handler: Rejects non-POST HTTP methods with 405 Method Not Allowed", async () => {
  const getReq = new Request("http://localhost:8000/send-push", {
    method: "GET",
  });
  const res = await handler(getReq);
  assertEquals(res.status, 405);
  const body = await res.json();
  assertEquals(body.error, "Method not allowed");
});

Deno.test("handler: Rejects requests missing environment configuration with safe 500 error", async () => {
  const postReq = new Request("http://localhost:8000/send-push", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ chat_id: "foo", message_id: "bar" }),
  });
  const res = await handler(postReq);
  assertEquals(res.status, 500);
  const body = await res.json();
  assertEquals(body.error, "Server configuration error");
  assertEquals(body.message, undefined); // No internal string leak
});

Deno.test("checkRateLimitRpc: Returns allowed: true when RPC permits request (within 30 req window)", async () => {
  const mockAdminClient = {
    rpc: async (name: string, params: Record<string, unknown>) => {
      assertEquals(name, "check_push_rate_limit");
      assertEquals(params.p_user_id, "user-valid-1");
      return {
        data: {
          allowed: true,
          current_count: 5,
          limit: 30,
          reset_seconds: 55,
          window_seconds: 60,
        },
        error: null,
      };
    },
  };

  const result = await checkRateLimitRpc(mockAdminClient, "user-valid-1");
  assertEquals(result.allowed, true);
  assertEquals(result.resetSeconds, 55);
  assertEquals(result.currentCount, 5);
  assertEquals(result.limit, 30);
  assertEquals(result.error, undefined);
});

Deno.test("checkRateLimitRpc: Returns allowed: false when RPC indicates limit exceeded (31st request)", async () => {
  const mockAdminClient = {
    rpc: async () => ({
      data: {
        allowed: false,
        current_count: 31,
        limit: 30,
        reset_seconds: 42,
        window_seconds: 60,
      },
      error: null,
    }),
  };

  const result = await checkRateLimitRpc(mockAdminClient, "user-exceeded");
  assertEquals(result.allowed, false);
  assertEquals(result.resetSeconds, 42);
  assertEquals(result.currentCount, 31);
  assertEquals(result.error, undefined);
});

Deno.test("checkRateLimitRpc: Fails closed when database RPC returns an error", async () => {
  const mockAdminClient = {
    rpc: async () => ({
      data: null,
      error: { message: "connection to database failed" },
    }),
  };

  const result = await checkRateLimitRpc(mockAdminClient, "user-err");
  assertEquals(result.allowed, false);
  assertEquals(result.error, "rpc_error");
});

Deno.test("checkRateLimitRpc: Fails closed when RPC throws unexpected exception", async () => {
  const mockAdminClient = {
    rpc: async () => {
      throw new Error("TCP socket closed abruptly");
    },
  };

  const result = await checkRateLimitRpc(mockAdminClient, "user-throw");
  assertEquals(result.allowed, false);
  assertEquals(result.error, "exception");
});

Deno.test("checkRateLimitRpc: Fails closed when RPC returns invalid payload shape", async () => {
  const mockAdminClient = {
    rpc: async () => ({
      data: { unexpected: "payload" },
      error: null,
    }),
  };

  const result = await checkRateLimitRpc(mockAdminClient, "user-malformed");
  assertEquals(result.allowed, false);
  assertEquals(result.error, "missing_allowed_field");
});

Deno.test("handler: Returns HTTP 429 Too Many Requests with Retry-After header when rate limit is exceeded", async () => {
  const mockUserClient = {
    auth: {
      getUser: async () => ({
        data: { user: { id: "caller-rate-limited" } },
        error: null,
      }),
    },
  };

  const mockAdminClient = {
    rpc: async () => ({
      data: {
        allowed: false,
        current_count: 31,
        limit: 30,
        reset_seconds: 37,
        window_seconds: 60,
      },
      error: null,
    }),
    from: () => ({ select: () => ({ eq: () => ({ maybeSingle: async () => ({}) }) }) }),
  };

  const req = new Request("http://localhost:8000/send-push", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: "Bearer mock-token-429",
    },
    body: JSON.stringify({
      chat_id: "c9ccc86c-cd42-40bb-8678-d9a30964ce30",
      message_id: "e2a4b880-9b36-4d22-9029-2182c1e7a5c1",
    }),
  });

  const res = await handler(req, {
    userClient: mockUserClient,
    adminClient: mockAdminClient,
  });

  assertEquals(res.status, 429);
  assertEquals(res.headers.get("Retry-After"), "37");
  const body = await res.json();
  assertEquals(body.error, "Too Many Requests: push dispatch rate limit exceeded");
  assertEquals(body.retryAfter, 37);
});

Deno.test("handler: Returns HTTP 503 Service Unavailable when rate limiter RPC fails (fail-closed)", async () => {
  const mockUserClient = {
    auth: {
      getUser: async () => ({
        data: { user: { id: "caller-degraded-db" } },
        error: null,
      }),
    },
  };

  const mockAdminClient = {
    rpc: async () => ({
      data: null,
      error: { message: "statement timeout" },
    }),
    from: () => ({ select: () => ({ eq: () => ({ maybeSingle: async () => ({}) }) }) }),
  };

  const req = new Request("http://localhost:8000/send-push", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: "Bearer mock-token-503",
    },
    body: JSON.stringify({
      chat_id: "c9ccc86c-cd42-40bb-8678-d9a30964ce30",
      message_id: "e2a4b880-9b36-4d22-9029-2182c1e7a5c1",
    }),
  });

  const res = await handler(req, {
    userClient: mockUserClient,
    adminClient: mockAdminClient,
  });

  assertEquals(res.status, 503);
  const body = await res.json();
  assertEquals(body.error, "Service Unavailable: push notification rate limit service unavailable");
});

Deno.test("handler: Distinguishes between 429 rate limit exceeded and 503 database degradation", async () => {
  // Test 1: Rate limit 429
  const rateLimitReq = new Request("http://localhost:8000/send-push", {
    method: "POST",
    headers: { Authorization: "Bearer tok", "Content-Type": "application/json" },
    body: JSON.stringify({ chat_id: "c9ccc86c-cd42-40bb-8678-d9a30964ce30", message_id: "e2a4b880-9b36-4d22-9029-2182c1e7a5c1" }),
  });
  const res429 = await handler(rateLimitReq, {
    userClient: { auth: { getUser: async () => ({ data: { user: { id: "u1" } }, error: null }) } },
    adminClient: { rpc: async () => ({ data: { allowed: false, reset_seconds: 15 }, error: null }), from: () => ({}) },
  });
  assertEquals(res429.status, 429);
  assertEquals(res429.headers.get("Retry-After"), "15");

  // Test 2: Database outage 503
  const outageReq = new Request("http://localhost:8000/send-push", {
    method: "POST",
    headers: { Authorization: "Bearer tok", "Content-Type": "application/json" },
    body: JSON.stringify({ chat_id: "c9ccc86c-cd42-40bb-8678-d9a30964ce30", message_id: "e2a4b880-9b36-4d22-9029-2182c1e7a5c1" }),
  });
  const res503 = await handler(outageReq, {
    userClient: { auth: { getUser: async () => ({ data: { user: { id: "u1" } }, error: null }) } },
    adminClient: { rpc: async () => ({ data: null, error: { message: "pool exhausted" } }), from: () => ({}) },
  });
  assertEquals(res503.status, 503);
  assertEquals(res503.headers.get("Retry-After"), null);
});

Deno.test("handler: Successfully constructs OneSignal REST API request with exact endpoint, Key auth, and include_subscription_ids", async () => {
  const callerUid = "11111111-1111-1111-1111-111111111111";
  const recipientUid = "22222222-2222-2222-2222-222222222222";
  const validChatId = "c9ccc86c-cd42-40bb-8678-d9a30964ce30";
  const validMsgId = "e2a4b880-9b36-4d22-9029-2182c1e7a5c1";
  const testSubId = "70142ddd-32be-40e0-b1ce-97a1b958e3f4";

  let capturedUrl = "";
  let capturedHeaders: Headers | null = null;
  let capturedBody: any = null;

  const mockFetcher: typeof fetch = async (input, init) => {
    capturedUrl = input.toString();
    capturedHeaders = new Headers(init?.headers);
    capturedBody = JSON.parse(init?.body as string);

    return new Response(JSON.stringify({ id: "os-notification-123", recipients: 1 }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  };

  const mockUserClient = {
    auth: {
      getUser: async () => ({
        data: { user: { id: callerUid } },
        error: null,
      }),
    },
  };

  const mockAdminClient = {
    rpc: async () => ({
      data: { allowed: true, reset_seconds: 60 },
      error: null,
    }),
    from: (table: string) => {
      if (table === "chat_members") {
        return {
          select: () => ({
            eq: (col: string, val: string) => ({
              eq: () => ({
                maybeSingle: async () => ({ data: { user_id: callerUid }, error: null }),
              }),
              neq: () => ({
                data: [{ user_id: recipientUid }],
                error: null,
              }),
            }),
          }),
        };
      }
      if (table === "messages") {
        return {
          select: () => ({
            eq: () => ({
              eq: () => ({
                maybeSingle: async () => ({
                  data: {
                    id: validMsgId,
                    chat_id: validChatId,
                    sender_id: callerUid,
                    type: "text",
                    text: "Hello there!",
                  },
                  error: null,
                }),
              }),
            }),
          }),
        };
      }
      if (table === "profiles") {
        return {
          select: () => ({
            eq: () => ({
              maybeSingle: async () => ({
                data: { display_name: "Alice", phone_e164: "+919876543210" },
                error: null,
              }),
            }),
          }),
        };
      }
      if (table === "user_devices") {
        return {
          select: () => ({
            in: () => ({
              eq: () => ({
                data: [{ player_id: testSubId, user_id: recipientUid, platform: "android" }],
                error: null,
              }),
            }),
          }),
        };
      }
      return {};
    },
  };

  // Set mock environment variables for test execution
  Deno.env.set("ONESIGNAL_APP_ID", "mock-app-id");
  Deno.env.set("ONESIGNAL_REST_KEY", "mock-rest-api-key");

  const req = new Request("http://localhost:8000/send-push", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: "Bearer mock-caller-jwt",
    },
    body: JSON.stringify({
      chat_id: validChatId,
      message_id: validMsgId,
    }),
  });

  const res = await handler(req, {
    userClient: mockUserClient,
    adminClient: mockAdminClient,
    fetcher: mockFetcher,
  });

  assertEquals(res.status, 200);
  const resJson = await res.json();
  assertEquals(resJson.success, true);
  assertEquals(resJson.delivered_count, 1);
  assertEquals(resJson.onesignal_recipients, 1);
  assertEquals(resJson.oneSignalId, "os-notification-123");

  // Assert exact modern OneSignal API contract
  assertEquals(capturedUrl, "https://api.onesignal.com/notifications");
  assertEquals(capturedHeaders?.get("Authorization"), "Key mock-rest-api-key");
  assertEquals(capturedBody?.include_subscription_ids, [testSubId]);
  assertEquals(capturedBody?.include_player_ids, undefined);
  assertEquals(capturedBody?.headings?.en, "+919876543210");
  assertEquals(capturedBody?.contents?.en, "Hello there!");
  assertEquals(capturedBody?.data?.senderPhone, "+919876543210");
  assertEquals(capturedBody?.data?.senderId, callerUid);
  assertEquals(capturedBody?.existing_android_channel_id, "chat_messages");
  assertEquals(capturedBody?.android_channel_id, undefined);
  assertEquals(capturedBody?.android_group, undefined);
  assertEquals(capturedBody?.priority, 10);
});

Deno.test("handler: Handles OneSignal HTTP 400 rejection with sanitized logging and HTTP 502 Bad Gateway", async () => {
  const callerUid = "11111111-1111-1111-1111-111111111111";
  const recipientUid = "22222222-2222-2222-2222-222222222222";
  const validChatId = "c9ccc86c-cd42-40bb-8678-d9a30964ce30";
  const validMsgId = "e2a4b880-9b36-4d22-9029-2182c1e7a5c1";
  const testSubId = "70142ddd-32be-40e0-b1ce-97a1b958e3f4";

  const mockFetcher: typeof fetch = async () => {
    return new Response(
      JSON.stringify({
        errors: ["Could not find android_channel_id", "sensitive_token_should_not_leak_to_client"],
      }),
      {
        status: 400,
        headers: { "Content-Type": "application/json" },
      }
    );
  };

  const mockUserClient = {
    auth: {
      getUser: async () => ({
        data: { user: { id: callerUid } },
        error: null,
      }),
    },
  };

  const mockAdminClient = {
    rpc: async () => ({ data: { allowed: true, reset_seconds: 60 }, error: null }),
    from: (table: string) => {
      if (table === "chat_members") {
        return {
          select: () => ({
            eq: () => ({
              eq: () => ({ maybeSingle: async () => ({ data: { user_id: callerUid }, error: null }) }),
              neq: () => ({ data: [{ user_id: recipientUid }], error: null }),
            }),
          }),
        };
      }
      if (table === "messages") {
        return {
          select: () => ({
            eq: () => ({
              eq: () => ({
                maybeSingle: async () => ({
                  data: {
                    id: validMsgId,
                    chat_id: validChatId,
                    sender_id: callerUid,
                    type: "text",
                    text: "Hello",
                  },
                  error: null,
                }),
              }),
            }),
          }),
        };
      }
      if (table === "profiles") {
        return { select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: { display_name: "Alice" }, error: null }) }) }) };
      }
      if (table === "user_devices") {
        return {
          select: () => ({
            in: () => ({
              eq: () => ({
                data: [{ player_id: testSubId, user_id: recipientUid, platform: "android" }],
                error: null,
              }),
            }),
          }),
        };
      }
      return {};
    },
  };

  Deno.env.set("ONESIGNAL_APP_ID", "mock-app-id");
  Deno.env.set("ONESIGNAL_REST_KEY", "mock-rest-api-key");

  const req = new Request("http://localhost:8000/send-push", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer mock-caller-jwt" },
    body: JSON.stringify({ chat_id: validChatId, message_id: validMsgId }),
  });

  const res = await handler(req, {
    userClient: mockUserClient,
    adminClient: mockAdminClient,
    fetcher: mockFetcher,
  });

  assertEquals(res.status, 502);
  const body = await res.json();
  assertEquals(body.error, "OneSignal API rejection");
  assertEquals(body.statusCode, 400);
  // Verify client is not exposed to raw provider errors
  assertEquals(body.errors, undefined);
});

Deno.test("handler: Filters out non-UUID / malformed subscription IDs and avoids provider invocation", async () => {
  const callerUid = "11111111-1111-1111-1111-111111111111";
  const recipientUid = "22222222-2222-2222-2222-222222222222";
  const validChatId = "c9ccc86c-cd42-40bb-8678-d9a30964ce30";
  const validMsgId = "e2a4b880-9b36-4d22-9029-2182c1e7a5c1";

  let fetcherCalled = false;
  const mockFetcher: typeof fetch = async () => {
    fetcherCalled = true;
    return new Response(JSON.stringify({}), { status: 200 });
  };

  const mockUserClient = {
    auth: { getUser: async () => ({ data: { user: { id: callerUid } }, error: null }) },
  };

  const mockAdminClient = {
    rpc: async () => ({ data: { allowed: true, reset_seconds: 60 }, error: null }),
    from: (table: string) => {
      if (table === "chat_members") {
        return {
          select: () => ({
            eq: () => ({
              eq: () => ({ maybeSingle: async () => ({ data: { user_id: callerUid }, error: null }) }),
              neq: () => ({ data: [{ user_id: recipientUid }], error: null }),
            }),
          }),
        };
      }
      if (table === "messages") {
        return {
          select: () => ({
            eq: () => ({
              eq: () => ({
                maybeSingle: async () => ({
                  data: {
                    id: validMsgId,
                    chat_id: validChatId,
                    sender_id: callerUid,
                    type: "text",
                    text: "Hello",
                  },
                  error: null,
                }),
              }),
            }),
          }),
        };
      }
      if (table === "profiles") {
        return { select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: { display_name: "Alice" }, error: null }) }) }) };
      }
      if (table === "user_devices") {
        return {
          select: () => ({
            in: () => ({
              eq: () => ({
                // Non-UUID strings: arbitrary short string, fcm token, empty
                data: [
                  { player_id: "player-uuid-001", user_id: recipientUid, platform: "android" },
                  { player_id: "legacy_fcm_token_12345", user_id: recipientUid, platform: "android" },
                  { player_id: "   ", user_id: recipientUid, platform: "android" },
                ],
                error: null,
              }),
            }),
          }),
        };
      }
      return {};
    },
  };

  Deno.env.set("ONESIGNAL_APP_ID", "mock-app-id");
  Deno.env.set("ONESIGNAL_REST_KEY", "mock-rest-api-key");

  const req = new Request("http://localhost:8000/send-push", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer mock-caller-jwt" },
    body: JSON.stringify({ chat_id: validChatId, message_id: validMsgId }),
  });

  const res = await handler(req, {
    userClient: mockUserClient,
    adminClient: mockAdminClient,
    fetcher: mockFetcher,
  });

  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.success, true);
  assertEquals(body.delivered_count, 0);
  assertEquals(body.reason, "no_valid_onesignal_subscriptions");
  assertEquals(fetcherCalled, false);
});

Deno.test("Calling Push Dispatch: Dispatches call invitation without leaking room_id", async () => {
  const callerUid = "e2a4b880-9b36-4d22-9029-2182c1e7a5c1";
  const validCallId = "550e8400-e29b-41d4-a716-446655440000";
  const recipientUid = "33333333-3333-4333-8333-333333333333";
  const validSubscriptionId = "11111111-2222-4333-8444-555555555555";

  let outboxUpdatedToDispatched = false;
  let dispatchedPayload: any = null;

  const mockUserClient = {
    auth: {
      getUser: async () => ({
        data: { user: { id: callerUid, phone: "+1234567890" } },
        error: null,
      }),
    },
  };

  const mockAdminClient = {
    rpc: async (name: string) => {
      if (name === "check_push_rate_limit") return { data: { allowed: true, reset_seconds: 60 }, error: null };
      return { data: null, error: null };
    },
    from: (table: string) => {
      if (table === "calls") {
        return {
          select: () => ({
            eq: () => ({
              maybeSingle: async () => ({
                data: { id: validCallId, caller_id: callerUid, status: "ringing" },
                error: null,
              }),
            }),
          }),
        };
      }
      if (table === "call_outbox") {
        const sampleOutbox = {
          id: "outbox-1",
          call_id: validCallId,
          event_type: "call_invitation",
          payload: {
            callId: validCallId,
            chatId: "chat-uuid-1",
            callerId: callerUid,
            callerName: "Alice",
            callType: "audio",
            inviteeIds: [recipientUid],
            isMidCall: false,
          },
          status: "pending",
          retry_count: 0,
          max_retries: 3,
        };

        return {
          select: () => {
            const b: any = {
              eq: () => b,
              in: () => b,
              or: () => b,
              order: () => b,
              limit: async () => ({
                data: [sampleOutbox],
                error: null,
              }),
            };
            return b;
          },
          update: (fields: any) => {
            const b: any = {
              eq: () => b,
              or: () => b,
              select: async () => ({
                data: [{ ...sampleOutbox, ...fields }],
                error: null,
              }),
              then: (resolve: any) => {
                if (fields.status === "dispatched") {
                  outboxUpdatedToDispatched = true;
                }
                return Promise.resolve({ error: null }).then(resolve);
              },
            };
            return b;
          },
        };
      }
      if (table === "user_devices") {
        return {
          select: () => ({
            in: () => ({
              eq: async () => ({
                data: [{ player_id: validSubscriptionId, user_id: recipientUid, platform: "android" }],
                error: null,
              }),
            }),
          }),
        };
      }
      return {};
    },
  };

  const mockFetcher = async (_url: string | URL | Request, init?: RequestInit) => {
    dispatchedPayload = JSON.parse(init?.body as string);
    return new Response(JSON.stringify({ id: "os-call-push-id", recipients: 1 }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  };

  Deno.env.set("ONESIGNAL_APP_ID", "mock-app-id");
  Deno.env.set("ONESIGNAL_REST_KEY", "mock-rest-api-key");

  const req = new Request("http://localhost:8000/send-push", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer mock-caller-jwt" },
    body: JSON.stringify({ call_id: validCallId }),
  });

  const res = await handler(req, {
    userClient: mockUserClient,
    adminClient: mockAdminClient,
    fetcher: mockFetcher,
  });

  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.success, true);
  assertEquals(body.dispatched_count, 1);
  assertEquals(outboxUpdatedToDispatched, true);

  // Security Verification: room_id is NEVER in data or payload
  assertEquals(dispatchedPayload !== null, true);
  assertEquals("room_id" in (dispatchedPayload?.data || {}), false);
  assertEquals("roomId" in (dispatchedPayload?.data || {}), false);
  assertEquals(dispatchedPayload.data.callId, validCallId);
  assertEquals(dispatchedPayload.data.type, "call");
  assertEquals(dispatchedPayload.existing_android_channel_id, "calls");
  assertEquals(dispatchedPayload.priority, 10);
});

Deno.test("Worker Authentication: Rejects worker actions when CALL_WORKER_SECRET is missing or wrong", async () => {
  const reqNoSecret = new Request("http://localhost:8000/send-push", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer user-jwt" },
    body: JSON.stringify({ action: "process_call_timeouts" }),
  });

  const resNoSecret = await handler(reqNoSecret, { callWorkerSecret: "correct-worker-secret" });
  assertEquals(resNoSecret.status, 403);
  const bodyNoSecret = await resNoSecret.json();
  assertEquals(bodyNoSecret.error, "Forbidden: invalid or missing worker secret");

  const reqWrongSecret = new Request("http://localhost:8000/send-push", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-call-worker-secret": "wrong-secret",
    },
    body: JSON.stringify({ action: "process_call_outbox" }),
  });

  const resWrongSecret = await handler(reqWrongSecret, { callWorkerSecret: "correct-worker-secret" });
  assertEquals(resWrongSecret.status, 403);
});

Deno.test("Worker Authentication: Authorizes worker actions with valid CALL_WORKER_SECRET", async () => {
  let timeoutRpcCalled = false;
  const mockAdminClient = {
    rpc: async (name: string, params: any) => {
      if (name === "process_call_timeouts") {
        timeoutRpcCalled = true;
        assertEquals(params.p_batch_size, 25);
        return { data: { success: true, processed_count: 3 }, error: null };
      }
      return { data: null, error: null };
    },
    from: () => ({}),
  };

  const req = new Request("http://localhost:8000/send-push", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-call-worker-secret": "super-secure-worker-secret",
    },
    body: JSON.stringify({ action: "process_call_timeouts" }),
  });

  const res = await handler(req, {
    adminClient: mockAdminClient,
    callWorkerSecret: "super-secure-worker-secret",
  });

  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.success, true);
  assertEquals(body.action, "process_call_timeouts");
  assertEquals(body.processed.processed_count, 3);
  assertEquals(timeoutRpcCalled, true);
});

// ==============================================================================
// STAGE 2.3: Branch 3 Safe Optimistic Lease Acquisition & Concurrency Tests
// ==============================================================================

Deno.test("Branch 3 Lease: Pending event is claimed and dispatched", async () => {
  const callerUid = "e2a4b880-9b36-4d22-9029-2182c1e7a5c1";
  const validCallId = "550e8400-e29b-41d4-a716-446655440001";
  let leaseAcquired = false;

  const mockAdminClient = {
    rpc: async () => ({ data: { allowed: true, reset_seconds: 60 }, error: null }),
    from: (table: string) => {
      if (table === "calls") {
        return {
          select: () => ({
            eq: () => ({
              maybeSingle: async () => ({ data: { id: validCallId, caller_id: callerUid, status: "ringing" }, error: null }),
            }),
          }),
        };
      }
      if (table === "call_outbox") {
        return {
          select: () => {
            const b: any = {
              eq: () => b,
              or: () => b,
              order: () => b,
              limit: async () => ({
                data: [{
                  id: "outbox-pending-1",
                  call_id: validCallId,
                  event_type: "call_invitation",
                  payload: { callId: validCallId, chatId: "chat-1", callerId: callerUid, callerName: "Alice", callType: "audio", inviteeIds: ["user-2"] },
                  status: "pending",
                  retry_count: 0,
                  max_retries: 3,
                }],
                error: null,
              }),
            };
            return b;
          },
          update: (fields: any) => {
            const b: any = {
              eq: () => b,
              or: () => b,
              select: async () => {
                if (fields.status === "processing") leaseAcquired = true;
                return { data: [{ id: "outbox-pending-1", status: "processing", locked_by: fields.locked_by }], error: null };
              },
            };
            return b;
          },
        };
      }
      if (table === "user_devices") {
        return {
          select: () => ({ in: () => ({ eq: async () => ({ data: [{ player_id: "11111111-2222-4333-8444-555555555555", user_id: "user-2", platform: "android" }], error: null }) }) }),
        };
      }
      return {};
    },
  };

  const req = new Request("http://localhost:8000/send-push", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer user-jwt" },
    body: JSON.stringify({ call_id: validCallId }),
  });

  const res = await handler(req, {
    userClient: { auth: { getUser: async () => ({ data: { user: { id: callerUid } }, error: null }) } },
    adminClient: mockAdminClient,
    fetcher: async () => new Response(JSON.stringify({ id: "msg-1" }), { status: 200 }),
  });

  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.success, true);
  assertEquals(body.dispatched_count, 1);
  assertEquals(leaseAcquired, true);
});

Deno.test("Branch 3 Lease: Active processing lease is ignored (in_progress_by_worker)", async () => {
  const callerUid = "e2a4b880-9b36-4d22-9029-2182c1e7a5c1";
  const validCallId = "550e8400-e29b-41d4-a716-446655440002";

  const mockAdminClient = {
    rpc: async () => ({ data: { allowed: true, reset_seconds: 60 }, error: null }),
    from: (table: string) => {
      if (table === "calls") {
        return {
          select: () => ({
            eq: () => ({ maybeSingle: async () => ({ data: { id: validCallId, caller_id: callerUid, status: "ringing" }, error: null }) }),
          }),
        };
      }
      if (table === "call_outbox") {
        return {
          select: () => {
            const b: any = {
              eq: () => b,
              or: () => b,
              gte: () => b,
              order: () => b,
              // First query (pending/expired) returns empty because lease is active
              limit: async () => ({
                data: [{ id: "outbox-active-1", status: "processing", locked_until: new Date(Date.now() + 25000).toISOString() }],
                error: null,
              }),
            };
            // For activeLease fallback check
            b.limit = async () => {
              if (b._isFirst) return { data: [], error: null };
              return { data: [{ id: "outbox-active-1", status: "processing" }], error: null };
            };
            b._isFirst = true;
            return b;
          },
        };
      }
      return {};
    },
  };

  const req = new Request("http://localhost:8000/send-push", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer user-jwt" },
    body: JSON.stringify({ call_id: validCallId }),
  });

  const res = await handler(req, {
    userClient: { auth: { getUser: async () => ({ data: { user: { id: callerUid } }, error: null }) } },
    adminClient: mockAdminClient,
  });

  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.success, true);
  assertEquals(body.dispatched_count, 0);
});

Deno.test("Branch 3 Lease: Expired processing lease is reclaimed and dispatched", async () => {
  const callerUid = "e2a4b880-9b36-4d22-9029-2182c1e7a5c1";
  const validCallId = "550e8400-e29b-41d4-a716-446655440003";
  let reclaimed = false;

  const mockAdminClient = {
    rpc: async () => ({ data: { allowed: true, reset_seconds: 60 }, error: null }),
    from: (table: string) => {
      if (table === "calls") {
        return {
          select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: { id: validCallId, caller_id: callerUid, status: "ringing" }, error: null }) }) }),
        };
      }
      if (table === "call_outbox") {
        return {
          select: () => {
            const b: any = {
              eq: () => b,
              or: () => b,
              order: () => b,
              limit: async () => ({
                data: [{
                  id: "outbox-expired-1",
                  call_id: validCallId,
                  event_type: "call_invitation",
                  payload: { callId: validCallId, chatId: "chat-1", callerId: callerUid, callerName: "Alice", callType: "audio", inviteeIds: ["user-2"] },
                  status: "processing",
                  locked_until: new Date(Date.now() - 5000).toISOString(),
                  retry_count: 1,
                  max_retries: 3,
                }],
                error: null,
              }),
            };
            return b;
          },
          update: () => {
            const b: any = {
              eq: () => b,
              or: () => b,
              select: async () => {
                reclaimed = true;
                return { data: [{ id: "outbox-expired-1", status: "processing" }], error: null };
              },
            };
            return b;
          },
        };
      }
      if (table === "user_devices") {
        return {
          select: () => ({ in: () => ({ eq: async () => ({ data: [{ player_id: "11111111-2222-4333-8444-555555555555", user_id: "user-2", platform: "android" }], error: null }) }) }),
        };
      }
      return {};
    },
  };

  const req = new Request("http://localhost:8000/send-push", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer user-jwt" },
    body: JSON.stringify({ call_id: validCallId }),
  });

  const res = await handler(req, {
    userClient: { auth: { getUser: async () => ({ data: { user: { id: callerUid } }, error: null }) } },
    adminClient: mockAdminClient,
    fetcher: async () => new Response(JSON.stringify({ id: "msg-reclaimed" }), { status: 200 }),
  });

  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.success, true);
  assertEquals(body.dispatched_count, 1);
  assertEquals(reclaimed, true);
});

Deno.test("Branch 3 Lease: Already dispatched event returns already_dispatched reason", async () => {
  const callerUid = "e2a4b880-9b36-4d22-9029-2182c1e7a5c1";
  const validCallId = "550e8400-e29b-41d4-a716-446655440004";

  let queryStep = 0;
  const mockAdminClient = {
    rpc: async () => ({ data: { allowed: true, reset_seconds: 60 }, error: null }),
    from: (table: string) => {
      if (table === "calls") {
        return { select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: { id: validCallId, caller_id: callerUid, status: "ringing" }, error: null }) }) }) };
      }
      if (table === "call_outbox") {
        return {
          select: () => {
            const b: any = {
              eq: () => b,
              or: () => b,
              order: () => b,
              limit: async () => {
                queryStep++;
                if (queryStep === 1) {
                  // No pending/expired rows
                  return { data: [], error: null };
                }
                // existingDispatched query returns 1 dispatched row
                return { data: [{ id: "outbox-disp-1", status: "dispatched" }], error: null };
              },
            };
            return b;
          },
        };
      }
      return {};
    },
  };

  const req = new Request("http://localhost:8000/send-push", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer user-jwt" },
    body: JSON.stringify({ call_id: validCallId }),
  });

  const res = await handler(req, {
    userClient: { auth: { getUser: async () => ({ data: { user: { id: callerUid } }, error: null }) } },
    adminClient: mockAdminClient,
  });

  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.success, true);
  assertEquals(body.reason, "already_dispatched");
  assertEquals(body.dispatched_count, 0);
});

Deno.test("Branch 3 Lease: Event with retry_count >= max_retries is skipped (terminal failure)", async () => {
  const callerUid = "e2a4b880-9b36-4d22-9029-2182c1e7a5c1";
  const validCallId = "550e8400-e29b-41d4-a716-446655440005";
  let attemptedUpdate = false;

  const mockAdminClient = {
    rpc: async () => ({ data: { allowed: true, reset_seconds: 60 }, error: null }),
    from: (table: string) => {
      if (table === "calls") {
        return { select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: { id: validCallId, caller_id: callerUid, status: "ringing" }, error: null }) }) }) };
      }
      if (table === "call_outbox") {
        return {
          select: () => {
            const b: any = {
              eq: () => b,
              or: () => b,
              order: () => b,
              limit: async () => ({
                data: [{
                  id: "outbox-max-1",
                  call_id: validCallId,
                  status: "pending",
                  retry_count: 3,
                  max_retries: 3,
                }],
                error: null,
              }),
            };
            return b;
          },
          update: () => {
            attemptedUpdate = true;
            return { eq: () => ({ or: () => ({ select: async () => ({ data: [], error: null }) }) }) };
          },
        };
      }
      return {};
    },
  };

  const req = new Request("http://localhost:8000/send-push", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer user-jwt" },
    body: JSON.stringify({ call_id: validCallId }),
  });

  const res = await handler(req, {
    userClient: { auth: { getUser: async () => ({ data: { user: { id: callerUid } }, error: null }) } },
    adminClient: mockAdminClient,
  });

  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.dispatched_count, 0);
  assertEquals(attemptedUpdate, false);
});

Deno.test("Branch 3 Lease: Concurrent race between two dispatchers (only winner claims)", async () => {
  const callerUid = "e2a4b880-9b36-4d22-9029-2182c1e7a5c1";
  const validCallId = "550e8400-e29b-41d4-a716-446655440006";
  let fetchCount = 0;

  // Simulate loser dispatcher: atomic update returns empty array (lost race to competitor)
  const mockAdminClientLoser = {
    rpc: async () => ({ data: { allowed: true, reset_seconds: 60 }, error: null }),
    from: (table: string) => {
      if (table === "calls") {
        return { select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: { id: validCallId, caller_id: callerUid, status: "ringing" }, error: null }) }) }) };
      }
      if (table === "call_outbox") {
        return {
          select: () => {
            const b: any = {
              eq: () => b,
              or: () => b,
              order: () => b,
              limit: async () => ({
                data: [{
                  id: "outbox-race-1",
                  call_id: validCallId,
                  status: "pending",
                  retry_count: 0,
                  max_retries: 3,
                }],
                error: null,
              }),
            };
            return b;
          },
          update: () => {
            // Atomic conditional update fails because competitor won race
            return {
              eq: () => ({
                or: () => ({
                  select: async () => ({ data: [], error: null }),
                }),
              }),
            };
          },
        };
      }
      return {};
    },
  };

  const req = new Request("http://localhost:8000/send-push", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer user-jwt" },
    body: JSON.stringify({ call_id: validCallId }),
  });

  const res = await handler(req, {
    userClient: { auth: { getUser: async () => ({ data: { user: { id: callerUid } }, error: null }) } },
    adminClient: mockAdminClientLoser,
    fetcher: async () => {
      fetchCount++;
      return new Response(JSON.stringify({ id: "race-msg" }), { status: 200 });
    },
  });

  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.dispatched_count, 0);
  assertEquals(fetchCount, 0); // Winner dispatched; loser skipped cleanly
});
