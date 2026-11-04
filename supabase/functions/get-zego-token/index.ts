// ==============================================================================
// Supabase Edge Function: get-zego-token
// Description: Secure, authenticated ZEGOCLOUD Token04 generation endpoint.
// Security:
//   1. Verifies caller JWT with Supabase Auth (rejects unauthenticated callers with 401).
//   2. Strictly maps caller identity to authenticated Supabase user.id (no impersonation).
//   3. Validates server-side ZEGO_APP_ID and ZEGO_SERVER_SECRET from environment secrets.
//   4. Enforces bounded expiration (min 60s, max 86400s, default 3600s).
//   5. Never leaks ServerSecret, stack traces, or internal configuration in responses.
//   6. Implements vetted official ZEGOCLOUD Token04 specification (AES-256-CBC).
// ==============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";
import { createCipheriv } from "node:crypto";
import { Buffer } from "node:buffer";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

export const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const MIN_EXPIRATION_SECONDS = 60;
export const MAX_EXPIRATION_SECONDS = 86400; // 24 hours
export const DEFAULT_EXPIRATION_SECONDS = 3600; // 1 hour
export const MAX_ROOM_ID_LENGTH = 128;

export interface Token04Payload {
  room_id?: string;
  privilege?: Record<number, number>;
  stream_id_list?: string[] | null;
}

export interface ZegoTokenConfig {
  appId: number;
  serverSecret: string;
}

export interface GetZegoTokenRequest {
  call_id?: string;
  room_id?: string;
  effective_time_in_seconds?: number;
  call_type?: "audio" | "video";
}

export interface GetZegoTokenResponse {
  token: string;
  app_id: number;
  user_id: string;
  room_id: string;
  call_id: string;
  expires_at: number;
}

/**
 * Validates ZEGOCLOUD server configuration from environment secrets.
 */
export function validateZegoConfig(envAppId?: string, envSecret?: string): ZegoTokenConfig | null {
  if (!envAppId || !envSecret) {
    return null;
  }

  const appId = parseInt(envAppId.trim(), 10);
  if (isNaN(appId) || appId <= 0) {
    return null;
  }

  const serverSecret = envSecret.trim();
  if (serverSecret.length !== 32) {
    return null;
  }

  return { appId, serverSecret };
}

/**
 * Generates a random 32-bit signed integer for nonce.
 */
function makeNonce(): number {
  const buf = new Int32Array(1);
  crypto.getRandomValues(buf);
  return buf[0];
}

/**
 * Generates a random 16-character IV string.
 */
function makeRandomIv(): string {
  const chars = "0123456789abcdefghijklmnopqrstuvwxyz";
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  let result = "";
  for (let i = 0; i < 16; i++) {
    result += chars.charAt(bytes[i] % chars.length);
  }
  return result;
}

/**
 * Generates ZEGOCLOUD Token04 binary token according to official specification.
 * AES-256-CBC encryption of JSON tokenInfo payload with IV prefix and expire timestamp.
 */
export function generateToken04(
  appId: number,
  userId: string,
  secret: string,
  effectiveTimeInSeconds: number,
  payload: string = "",
): string {
  if (!appId || typeof appId !== "number" || appId <= 0) {
    throw new Error("Invalid appId");
  }

  if (!userId || typeof userId !== "string" || userId.trim().length === 0) {
    throw new Error("Invalid userId");
  }

  if (!secret || typeof secret !== "string" || secret.length !== 32) {
    throw new Error("Secret must be a 32-byte string");
  }

  if (!effectiveTimeInSeconds || typeof effectiveTimeInSeconds !== "number" || effectiveTimeInSeconds <= 0) {
    throw new Error("Invalid effectiveTimeInSeconds");
  }

  const createTime = Math.floor(Date.now() / 1000);
  const expireTime = createTime + effectiveTimeInSeconds;

  const tokenInfo = {
    app_id: appId,
    user_id: userId,
    nonce: makeNonce(),
    ctime: createTime,
    expire: expireTime,
    payload: payload || "",
  };

  const plainText = JSON.stringify(tokenInfo);
  const iv = makeRandomIv();

  // AES-256-CBC encryption
  const cipher = createCipheriv("aes-256-cbc", Buffer.from(secret, "utf8"), Buffer.from(iv, "utf8"));
  cipher.setAutoPadding(true);
  const encrypted = cipher.update(plainText, "utf8");
  const final = cipher.final();
  const encryptBuf = Buffer.concat([encrypted, final]);

  // Binary packing layout:
  // [8 bytes: BigInt64 expire] + [2 bytes: Uint16 iv length] + [iv bytes] + [2 bytes: Uint16 cipher length] + [cipher bytes]
  const b1 = new Uint8Array(8);
  const b2 = new Uint8Array(2);
  const b3 = new Uint8Array(2);

  new DataView(b1.buffer).setBigInt64(0, BigInt(tokenInfo.expire), false);
  new DataView(b2.buffer).setUint16(0, iv.length, false);
  new DataView(b3.buffer).setUint16(0, encryptBuf.byteLength, false);

  const packedBuffer = Buffer.concat([
    Buffer.from(b1),
    Buffer.from(b2),
    Buffer.from(iv, "utf8"),
    Buffer.from(b3),
    encryptBuf,
  ]);

  return "04" + packedBuffer.toString("base64");
}

export interface HandlerDependencies {
  userClient?: SupabaseClient | {
    auth: {
      getUser: (token?: string) => Promise<{ data: { user: { id: string } | null }; error: unknown }>;
    };
  };
  adminClient?: SupabaseClient | {
    from: (table: string) => any;
  };
  envConfig?: ZegoTokenConfig;
}

export async function handler(req: Request, deps?: HandlerDependencies): Promise<Response> {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: corsHeaders,
    });
  }

  try {
    // 1. Resolve ZEGOCLOUD configuration from secrets
    const zegoConfig = deps?.envConfig ?? validateZegoConfig(
      Deno.env.get("ZEGO_APP_ID"),
      Deno.env.get("ZEGO_SERVER_SECRET"),
    );

    if (!zegoConfig) {
      console.error("[get-zego-token] Missing or invalid ZEGO_APP_ID or ZEGO_SERVER_SECRET in server secrets");
      return new Response(
        JSON.stringify({ error: "Server configuration error" }),
        { status: 500, headers: corsHeaders },
      );
    }

    // 2. Authenticate caller identity via Supabase JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(
        JSON.stringify({ error: "Unauthorized: missing or invalid Authorization header" }),
        { status: 401, headers: corsHeaders },
      );
    }

    const token = authHeader.replace("Bearer ", "").trim();
    if (!token) {
      return new Response(
        JSON.stringify({ error: "Unauthorized: empty bearer token" }),
        { status: 401, headers: corsHeaders },
      );
    }

    let callerId: string;

    if (deps?.userClient) {
      const { data: { user }, error: authError } = await deps.userClient.auth.getUser(token);
      if (authError || !user) {
        return new Response(
          JSON.stringify({ error: "Unauthorized: token verification failed" }),
          { status: 401, headers: corsHeaders },
        );
      }
      callerId = user.id;
    } else {
      const supabaseUrl = Deno.env.get("SUPABASE_URL");
      const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");

      if (!supabaseUrl || !supabaseAnonKey) {
        console.error("[get-zego-token] Missing SUPABASE_URL or SUPABASE_ANON_KEY");
        return new Response(
          JSON.stringify({ error: "Server configuration error" }),
          { status: 500, headers: corsHeaders },
        );
      }

      const client = createClient(supabaseUrl, supabaseAnonKey, {
        global: { headers: { Authorization: `Bearer ${token}` } },
      });

      const { data: { user }, error: authError } = await client.auth.getUser();
      if (authError || !user) {
        return new Response(
          JSON.stringify({ error: "Unauthorized: token verification failed" }),
          { status: 401, headers: corsHeaders },
        );
      }
      callerId = user.id;
    }

    // 3. Parse and validate request parameters
    let body: GetZegoTokenRequest = {};
    const text = await req.text();
    if (text.trim().length > 0) {
      try {
        body = JSON.parse(text);
      } catch (_) {
        return new Response(
          JSON.stringify({ error: "Invalid JSON payload" }),
          { status: 400, headers: corsHeaders },
        );
      }
    }

    // Mandatory: call_id validation
    if (!body.call_id || typeof body.call_id !== "string" || !UUID_REGEX.test(body.call_id.trim())) {
      return new Response(
        JSON.stringify({ error: "Bad Request: valid UUID call_id is required" }),
        { status: 400, headers: corsHeaders },
      );
    }
    const callId = body.call_id.trim();

    // Sanitize effective time
    let effectiveSeconds = DEFAULT_EXPIRATION_SECONDS;
    if (body.effective_time_in_seconds !== undefined) {
      if (
        typeof body.effective_time_in_seconds !== "number" ||
        body.effective_time_in_seconds < MIN_EXPIRATION_SECONDS ||
        body.effective_time_in_seconds > MAX_EXPIRATION_SECONDS
      ) {
        return new Response(
          JSON.stringify({
            error: `Invalid effective_time_in_seconds: must be between ${MIN_EXPIRATION_SECONDS} and ${MAX_EXPIRATION_SECONDS}`,
          }),
          { status: 400, headers: corsHeaders },
        );
      }
      effectiveSeconds = Math.floor(body.effective_time_in_seconds);
    }

    // 4. Authoritative Call & Participant Verification
    let adminClient: any;
    if (deps?.adminClient) {
      adminClient = deps.adminClient;
    } else {
      const supabaseUrl = Deno.env.get("SUPABASE_URL");
      const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

      if (!supabaseUrl || !supabaseServiceRoleKey) {
        console.error("[get-zego-token] Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
        return new Response(
          JSON.stringify({ error: "Server configuration error" }),
          { status: 500, headers: corsHeaders },
        );
      }
      adminClient = createClient(supabaseUrl, supabaseServiceRoleKey);
    }

    // Verify call exists and is in an active state
    const { data: callRecord, error: callError } = await adminClient
      .from("calls")
      .select("id, status, room_id")
      .eq("id", callId)
      .maybeSingle();

    if (callError || !callRecord) {
      return new Response(
        JSON.stringify({ error: "Call not found" }),
        { status: 404, headers: corsHeaders },
      );
    }

    if (!["ringing", "ongoing"].includes(callRecord.status)) {
      return new Response(
        JSON.stringify({ error: `Call is not active (status: ${callRecord.status})` }),
        { status: 403, headers: corsHeaders },
      );
    }

    // Verify caller is a participant and has accepted the call
    const { data: participantRecord, error: partError } = await adminClient
      .from("call_participants")
      .select("id, status")
      .eq("call_id", callId)
      .eq("user_id", callerId)
      .maybeSingle();

    if (partError || !participantRecord) {
      return new Response(
        JSON.stringify({ error: "Forbidden: caller is not an invited or active participant in this call" }),
        { status: 403, headers: corsHeaders },
      );
    }

    if (participantRecord.status !== "accepted") {
      return new Response(
        JSON.stringify({
          error: `Forbidden: participant status must be accepted to acquire calling token (current: ${participantRecord.status})`,
        }),
        { status: 403, headers: corsHeaders },
      );
    }

    // 5. Authoritative Room ID binding (disregards any client-supplied room_id)
    const authoritativeRoomId = callRecord.room_id;
    const payloadObj: Token04Payload = {
      room_id: authoritativeRoomId,
      privilege: {
        1: 1, // Allow login room
        2: 1, // Allow publish stream
      },
    };
    const payload = JSON.stringify(payloadObj);

    // 6. Generate Token04 strictly mapped to the authenticated caller identity and room
    const zegoToken = generateToken04(
      zegoConfig.appId,
      callerId,
      zegoConfig.serverSecret,
      effectiveSeconds,
      payload,
    );

    const now = Math.floor(Date.now() / 1000);
    const expiresAt = now + effectiveSeconds;

    const responsePayload: GetZegoTokenResponse = {
      token: zegoToken,
      app_id: zegoConfig.appId,
      user_id: callerId,
      room_id: authoritativeRoomId,
      call_id: callId,
      expires_at: expiresAt,
    };

    return new Response(JSON.stringify(responsePayload), {
      status: 200,
      headers: corsHeaders,
    });
  } catch (err: unknown) {
    console.error("[get-zego-token] Unexpected error during token generation");
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: corsHeaders },
    );
  }
}

// Start HTTP listener on standard Deno server port
if (import.meta.main) {
  serve((req: Request) => handler(req));
}
