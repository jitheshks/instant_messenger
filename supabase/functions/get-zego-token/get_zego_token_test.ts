import { assertEquals, assertRejects } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  generateToken04,
  validateZegoConfig,
  handler,
  MIN_EXPIRATION_SECONDS,
  MAX_EXPIRATION_SECONDS,
  DEFAULT_EXPIRATION_SECONDS,
} from "./index.ts";

const VALID_APP_ID = 123456789;
const VALID_SECRET = "12345678901234567890123456789012"; // strictly 32 bytes
const VALID_USER_ID = "e2a4b880-9b36-4d22-9029-2182c1e7a5c1";
const VALID_CALL_ID = "a1b2c3d4-e5f6-4a1b-8c2d-3e4f5a6b7c8d";
const AUTHORITATIVE_ROOM_ID = "room-authoritative-uuid-9999";

Deno.test("validateZegoConfig: accepts valid numeric App ID and 32-byte secret", () => {
  const config = validateZegoConfig("123456789", VALID_SECRET);
  assertEquals(config !== null, true);
  assertEquals(config?.appId, 123456789);
  assertEquals(config?.serverSecret, VALID_SECRET);
});

Deno.test("validateZegoConfig: rejects invalid or missing configuration", () => {
  assertEquals(validateZegoConfig(undefined, VALID_SECRET), null);
  assertEquals(validateZegoConfig("not-a-number", VALID_SECRET), null);
  assertEquals(validateZegoConfig("-10", VALID_SECRET), null);
  assertEquals(validateZegoConfig("123456", "too-short-secret"), null);
  assertEquals(validateZegoConfig("123456", "a".repeat(33)), null);
});

Deno.test("generateToken04: produces valid token with '04' prefix", () => {
  const token = generateToken04(VALID_APP_ID, VALID_USER_ID, VALID_SECRET, 3600);
  assertEquals(token.startsWith("04"), true);
  assertEquals(token.length > 50, true);
});

Deno.test("generateToken04: rejects invalid arguments", () => {
  // @ts-ignore
  assertRejects(async () => generateToken04(0, VALID_USER_ID, VALID_SECRET, 3600));
  // @ts-ignore
  assertRejects(async () => generateToken04(VALID_APP_ID, "", VALID_SECRET, 3600));
  // @ts-ignore
  assertRejects(async () => generateToken04(VALID_APP_ID, VALID_USER_ID, "short", 3600));
  // @ts-ignore
  assertRejects(async () => generateToken04(VALID_APP_ID, VALID_USER_ID, VALID_SECRET, 0));
});

Deno.test("handler: returns 405 for non-POST methods", async () => {
  const req = new Request("http://localhost/get-zego-token", { method: "GET" });
  const res = await handler(req);
  assertEquals(res.status, 405);
});

Deno.test("handler: returns 500 when server secrets are unconfigured", async () => {
  const req = new Request("http://localhost/get-zego-token", {
    method: "POST",
    headers: { Authorization: "Bearer test-jwt" },
  });
  const res = await handler(req, { envConfig: undefined });
  assertEquals(res.status, 500);
  const data = await res.json();
  assertEquals(data.error, "Server configuration error");
});

Deno.test("handler: returns 401 when Authorization header is missing or malformed", async () => {
  const validConfig = { appId: VALID_APP_ID, serverSecret: VALID_SECRET };

  const reqNoAuth = new Request("http://localhost/get-zego-token", {
    method: "POST",
  });
  const resNoAuth = await handler(reqNoAuth, { envConfig: validConfig });
  assertEquals(resNoAuth.status, 401);

  const reqBadAuth = new Request("http://localhost/get-zego-token", {
    method: "POST",
    headers: { Authorization: "Basic dXNlcjpwYXNz" },
  });
  const resBadAuth = await handler(reqBadAuth, { envConfig: validConfig });
  assertEquals(resBadAuth.status, 401);
});

Deno.test("handler: returns 400 on malformed JSON payload", async () => {
  const validConfig = { appId: VALID_APP_ID, serverSecret: VALID_SECRET };
  const mockUserClient = {
    auth: {
      getUser: async (_token?: string) => ({
        data: { user: { id: VALID_USER_ID } },
        error: null,
      }),
    },
  } as any;

  const req = new Request("http://localhost/get-zego-token", {
    method: "POST",
    headers: {
      Authorization: "Bearer valid-token",
      "Content-Type": "application/json",
    },
    body: "{ malformed json",
  });

  const res = await handler(req, {
    envConfig: validConfig,
    userClient: mockUserClient,
  });
  assertEquals(res.status, 400);
});

Deno.test("handler: returns 400 when call_id is missing or not a valid UUID", async () => {
  const validConfig = { appId: VALID_APP_ID, serverSecret: VALID_SECRET };
  const mockUserClient = {
    auth: {
      getUser: async (_token?: string) => ({
        data: { user: { id: VALID_USER_ID } },
        error: null,
      }),
    },
  } as any;

  // Missing call_id
  const reqMissing = new Request("http://localhost/get-zego-token", {
    method: "POST",
    headers: { Authorization: "Bearer valid-token" },
    body: JSON.stringify({}),
  });
  const resMissing = await handler(reqMissing, {
    envConfig: validConfig,
    userClient: mockUserClient,
  });
  assertEquals(resMissing.status, 400);

  // Non-UUID call_id
  const reqBad = new Request("http://localhost/get-zego-token", {
    method: "POST",
    headers: { Authorization: "Bearer valid-token" },
    body: JSON.stringify({ call_id: "not-a-valid-uuid" }),
  });
  const resBad = await handler(reqBad, {
    envConfig: validConfig,
    userClient: mockUserClient,
  });
  assertEquals(resBad.status, 400);
});

Deno.test("handler: returns 400 when effective_time_in_seconds is out of bounds", async () => {
  const validConfig = { appId: VALID_APP_ID, serverSecret: VALID_SECRET };
  const mockUserClient = {
    auth: {
      getUser: async (_token?: string) => ({
        data: { user: { id: VALID_USER_ID } },
        error: null,
      }),
    },
  } as any;

  // Too low (< 60)
  const reqLow = new Request("http://localhost/get-zego-token", {
    method: "POST",
    headers: { Authorization: "Bearer valid-token" },
    body: JSON.stringify({ call_id: VALID_CALL_ID, effective_time_in_seconds: 10 }),
  });
  const resLow = await handler(reqLow, {
    envConfig: validConfig,
    userClient: mockUserClient,
  });
  assertEquals(resLow.status, 400);

  // Too high (> 86400)
  const reqHigh = new Request("http://localhost/get-zego-token", {
    method: "POST",
    headers: { Authorization: "Bearer valid-token" },
    body: JSON.stringify({ call_id: VALID_CALL_ID, effective_time_in_seconds: 999999 }),
  });
  const resHigh = await handler(reqHigh, {
    envConfig: validConfig,
    userClient: mockUserClient,
  });
  assertEquals(resHigh.status, 400);
});

Deno.test("handler: returns 404 when call does not exist", async () => {
  const validConfig = { appId: VALID_APP_ID, serverSecret: VALID_SECRET };
  const mockUserClient = {
    auth: {
      getUser: async () => ({ data: { user: { id: VALID_USER_ID } }, error: null }),
    },
  } as any;
  const mockAdminClient = {
    from: (_table: string) => ({
      select: () => ({
        eq: () => ({
          maybeSingle: async () => ({ data: null, error: null }),
        }),
      }),
    }),
  } as any;

  const req = new Request("http://localhost/get-zego-token", {
    method: "POST",
    headers: { Authorization: "Bearer valid-token" },
    body: JSON.stringify({ call_id: VALID_CALL_ID }),
  });
  const res = await handler(req, {
    envConfig: validConfig,
    userClient: mockUserClient,
    adminClient: mockAdminClient,
  });
  assertEquals(res.status, 404);
});

Deno.test("handler: returns 403 when call is terminated or not active", async () => {
  const validConfig = { appId: VALID_APP_ID, serverSecret: VALID_SECRET };
  const mockUserClient = {
    auth: {
      getUser: async () => ({ data: { user: { id: VALID_USER_ID } }, error: null }),
    },
  } as any;
  const mockAdminClient = {
    from: (_table: string) => ({
      select: () => ({
        eq: () => ({
          maybeSingle: async () => ({
            data: { id: VALID_CALL_ID, status: "ended", room_id: AUTHORITATIVE_ROOM_ID },
            error: null,
          }),
        }),
      }),
    }),
  } as any;

  const req = new Request("http://localhost/get-zego-token", {
    method: "POST",
    headers: { Authorization: "Bearer valid-token" },
    body: JSON.stringify({ call_id: VALID_CALL_ID }),
  });
  const res = await handler(req, {
    envConfig: validConfig,
    userClient: mockUserClient,
    adminClient: mockAdminClient,
  });
  assertEquals(res.status, 403);
});

Deno.test("handler: returns 403 when caller is not an accepted participant", async () => {
  const validConfig = { appId: VALID_APP_ID, serverSecret: VALID_SECRET };
  const mockUserClient = {
    auth: {
      getUser: async () => ({ data: { user: { id: VALID_USER_ID } }, error: null }),
    },
  } as any;

  // Participant status is 'invited', not 'accepted'
  const mockAdminClient = {
    from: (table: string) => ({
      select: () => ({
        eq: () => ({
          eq: () => ({
            maybeSingle: async () => {
              if (table === "call_participants") {
                return { data: { id: "p-1", status: "invited" }, error: null };
              }
              return { data: null, error: null };
            },
          }),
          maybeSingle: async () => {
            if (table === "calls") {
              return { data: { id: VALID_CALL_ID, status: "ringing", room_id: AUTHORITATIVE_ROOM_ID }, error: null };
            }
            return { data: null, error: null };
          },
        }),
      }),
    }),
  } as any;

  const req = new Request("http://localhost/get-zego-token", {
    method: "POST",
    headers: { Authorization: "Bearer valid-token" },
    body: JSON.stringify({ call_id: VALID_CALL_ID }),
  });
  const res = await handler(req, {
    envConfig: validConfig,
    userClient: mockUserClient,
    adminClient: mockAdminClient,
  });
  assertEquals(res.status, 403);
});

Deno.test("handler: successfully returns token bound to authoritative room for accepted participant", async () => {
  const validConfig = { appId: VALID_APP_ID, serverSecret: VALID_SECRET };
  const mockUserClient = {
    auth: {
      getUser: async () => ({ data: { user: { id: VALID_USER_ID } }, error: null }),
    },
  } as any;

  const mockAdminClient = {
    from: (table: string) => ({
      select: () => ({
        eq: () => ({
          eq: () => ({
            maybeSingle: async () => {
              if (table === "call_participants") {
                return { data: { id: "p-1", status: "accepted" }, error: null };
              }
              return { data: null, error: null };
            },
          }),
          maybeSingle: async () => {
            if (table === "calls") {
              return { data: { id: VALID_CALL_ID, status: "ringing", room_id: AUTHORITATIVE_ROOM_ID }, error: null };
            }
            return { data: null, error: null };
          },
        }),
      }),
    }),
  } as any;

  // Attacker attempts to pass spoofed user_id or spoofed room_id
  const req = new Request("http://localhost/get-zego-token", {
    method: "POST",
    headers: { Authorization: "Bearer valid-token" },
    body: JSON.stringify({
      call_id: VALID_CALL_ID,
      user_id: "attacker-spoofed-identity",
      room_id: "attacker-spoofed-room-id",
      effective_time_in_seconds: 1800,
    }),
  });

  const res = await handler(req, {
    envConfig: validConfig,
    userClient: mockUserClient,
    adminClient: mockAdminClient,
  });

  assertEquals(res.status, 200);
  const data = await res.json();
  assertEquals(data.app_id, VALID_APP_ID);
  assertEquals(data.user_id, VALID_USER_ID);
  assertEquals(data.call_id, VALID_CALL_ID);
  // Authoritative room binding from database record, spoofed room ignored
  assertEquals(data.room_id, AUTHORITATIVE_ROOM_ID);
  assertEquals(data.token.startsWith("04"), true);
  assertEquals(typeof data.expires_at, "number");
});
