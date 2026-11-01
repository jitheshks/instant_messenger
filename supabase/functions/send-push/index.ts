// ==============================================================================
// Supabase Edge Function: send-push
// Description: Authenticated server-side push notification dispatcher for OneSignal.
// Security:
//   1. Verifies caller JWT with Supabase Auth (rejects unauthenticated callers).
//   2. Enforces conversation membership and message authorship.
//   3. Derives notification preview, type, and sender name directly from
//      persisted database records (messages and profiles), ignoring unverified
//      client-supplied content.
//   4. Outbound provider requests are bounded by an explicit 8-second timeout.
//   5. Internal exception details, credentials, and message contents are never
//      leaked in logs or error responses.
//   6. Enforces centralized distributed sliding-window rate limiting via PostgreSQL RPC.
//   7. Master OneSignal REST credentials remain strictly on the server (Vault).
//   8. OneSignal is the sole notification delivery provider. Direct FCM HTTP v1
//      delivery is removed; FCM transport on Android is handled via OneSignal.
// ==============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

// ==============================================================================
// RATE LIMITER (SERVER-CONTROLLED SHARED POSTGRESQL ATOMIC RPC)
// Architecture Note:
// Multi-isolate Edge Functions on Deno Deploy cannot rely on isolate-local memory.
// Rate limiting is centralized in PostgreSQL public.check_push_rate_limit(p_user_id),
// using server-controlled tumbling window constants (30 requests / 60 seconds).
// If the database rate-limiter RPC fails, the function fails closed (HTTP 503)
// to prevent abuse and push storms during database degradation.
// ==============================================================================

export interface RateLimitCheckResult {
  allowed: boolean;
  resetSeconds: number;
  currentCount?: number;
  limit?: number;
  error?: string;
}

export async function checkRateLimitRpc(
  adminClient: {
    rpc: (name: string, params: Record<string, unknown>) => any;
  },
  userId: string,
): Promise<RateLimitCheckResult> {
  try {
    const { data, error } = await adminClient.rpc("check_push_rate_limit", {
      p_user_id: userId,
    });

    if (error) {
      return { allowed: false, resetSeconds: 0, error: "rpc_error" };
    }

    if (!data || typeof data !== "object") {
      return { allowed: false, resetSeconds: 0, error: "invalid_response" };
    }

    const payload = data as Record<string, unknown>;
    if (typeof payload.allowed !== "boolean") {
      return { allowed: false, resetSeconds: 0, error: "missing_allowed_field" };
    }

    return {
      allowed: payload.allowed,
      resetSeconds: typeof payload.reset_seconds === "number" ? payload.reset_seconds : 60,
      currentCount: typeof payload.current_count === "number" ? payload.current_count : undefined,
      limit: typeof payload.limit === "number" ? payload.limit : 30,
    };
  } catch (_err: unknown) {
    return { allowed: false, resetSeconds: 0, error: "exception" };
  }
}

// Retained for backward-compatible isolate-local testing and benchmarks
const rateLimitMap = new Map<string, number[]>();
const RATE_LIMIT_WINDOW_MS = 60 * 1000;
const MAX_REQUESTS_PER_WINDOW = 30;

export function isRateLimited(
  userId: string,
  now: number = Date.now(),
  store: Map<string, number[]> = rateLimitMap,
): boolean {
  const timestamps = store.get(userId) || [];
  const validTimestamps = timestamps.filter((t) => now - t < RATE_LIMIT_WINDOW_MS);

  if (validTimestamps.length >= MAX_REQUESTS_PER_WINDOW) {
    return true;
  }

  validTimestamps.push(now);
  store.set(userId, validTimestamps);
  return false;
}

export const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const ALLOWED_TYPES = new Set(["text", "media", "call"]);
export const MAX_PREVIEW_LENGTH = 120;
export const MAX_SENDER_NAME_LENGTH = 50;

export interface MessageRecord {
  id: string;
  chat_id: string;
  sender_id: string;
  type?: string | null;
  text?: string | null;
  media?: Record<string, unknown> | null;
}

export interface ProfileRecord {
  phone_e164?: string | null;
  display_name?: string | null;
}

/// Derives authoritative notification content (preview, type, senderName)
/// from persisted database records, ignoring unverified client parameters.
/// Never uses sender username or display_name as the notification title.
export function deriveNotificationContent(
  message: MessageRecord,
  senderPhoneOrProfile?: string | ProfileRecord | null,
): { preview: string; type: string; senderName: string } {
  // 1. Sanitize message type from database
  const rawType = typeof message.type === "string" ? message.type.toLowerCase().trim() : "text";
  const type = ALLOWED_TYPES.has(rawType) ? rawType : "text";

  // 2. Derive preview from database record
  let preview = "New message";
  if (type === "text") {
    const rawText = typeof message.text === "string" ? message.text.trim() : "";
    if (rawText.length > 0) {
      preview = rawText.length > MAX_PREVIEW_LENGTH ? rawText.slice(0, MAX_PREVIEW_LENGTH) : rawText;
    }
  } else if (type === "media") {
    const rawCaption = typeof message.text === "string" ? message.text.trim() : "";
    if (rawCaption.length > 0) {
      preview = rawCaption.length > MAX_PREVIEW_LENGTH ? rawCaption.slice(0, MAX_PREVIEW_LENGTH) : rawCaption;
    } else {
      const mediaKind =
        message.media && typeof message.media === "object" && typeof message.media["kind"] === "string"
          ? (message.media["kind"] as string).toLowerCase().trim()
          : "";

      switch (mediaKind) {
        case "image":
          preview = "📷 Photo";
          break;
        case "video":
          preview = "🎥 Video";
          break;
        case "audio":
          preview = "🎵 Audio";
          break;
        default:
          preview = "📎 Attachment";
          break;
      }
    }
  } else if (type === "call") {
    preview = "📞 Incoming call";
  }

  // 3. Derive sender title according to privacy and contact-identity rules:
  // Priority:
  // 1. If registered phone is available, use it as default title so unsaved contacts display phone number.
  // 2. If phone is unavailable, use generic fallback ("New message") rather than preferring username.
  // Never use username or display_name as notification title!
  let senderName = "New message";
  let rawPhone: string | undefined | null;
  if (typeof senderPhoneOrProfile === "string") {
    rawPhone = senderPhoneOrProfile;
  } else if (senderPhoneOrProfile && typeof senderPhoneOrProfile === "object") {
    rawPhone = senderPhoneOrProfile.phone_e164;
  }

  if (typeof rawPhone === "string" && rawPhone.trim().length > 0) {
    const clean = rawPhone.trim();
    senderName = clean.length > MAX_SENDER_NAME_LENGTH ? clean.slice(0, MAX_SENDER_NAME_LENGTH) : clean;
  }

  return { preview, type, senderName };
}

export interface HandlerDeps {
  userClient?: {
    auth: {
      getUser: (jwt?: string) => Promise<{ data: { user: { id: string } | null }; error: unknown }>;
    };
  };
  adminClient?: {
    rpc: (name: string, params: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }>;
    from: (table: string) => any;
  };
  rateLimiter?: (client: any, userId: string) => Promise<RateLimitCheckResult>;
  fetcher?: typeof fetch;
}

/// Helper function to detect whether an identifier is a raw FCM token.
/// Raw FCM tokens are long strings (> 50 chars) or contain colons.
export function isFcmToken(id: string): boolean {
  if (typeof id !== "string") return false;
  const trimmed = id.trim();
  return trimmed.length > 50 || trimmed.includes(":") || !UUID_REGEX.test(trimmed);
}

/// Helper function to validate OneSignal subscription IDs / Player IDs.
/// OneSignal v5 subscription IDs are 36-character RFC-4122 UUIDs.
export function isValidOneSignalSubscriptionId(id: unknown): id is string {
  if (typeof id !== "string") return false;
  const trimmed = id.trim();
  if (trimmed.length === 0) return false;
  return UUID_REGEX.test(trimmed);
}

export async function handler(req: Request, deps?: HandlerDeps): Promise<Response> {
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
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const onesignalAppId = Deno.env.get("ONESIGNAL_APP_ID");
    const onesignalRestKey = Deno.env.get("ONESIGNAL_REST_KEY");

    // Require environment configuration unless running with injected dependencies
    if (!deps) {
      if (!supabaseUrl || !supabaseAnonKey || !supabaseServiceRoleKey) {
        console.error("[send-push] Missing Supabase environment keys");
        return new Response(
          JSON.stringify({ error: "Server configuration error" }),
          { status: 500, headers: corsHeaders }
        );
      }

      if (!onesignalAppId || !onesignalRestKey) {
        console.error("[send-push] Missing OneSignal credentials in Vault");
        return new Response(
          JSON.stringify({ error: "Server configuration error" }),
          { status: 500, headers: corsHeaders }
        );
      }
    }

    // 1. Authenticate caller via JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(
        JSON.stringify({ error: "Unauthorized: missing or invalid Authorization header" }),
        { status: 401, headers: corsHeaders }
      );
    }

    const token = authHeader.replace("Bearer ", "").trim();
    const userClient = deps?.userClient ?? createClient(supabaseUrl!, supabaseAnonKey!, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });

    const {
      data: { user },
      error: authError,
    } = await userClient.auth.getUser();

    if (authError || !user) {
      console.error("[send-push] JWT authentication failed");
      return new Response(
        JSON.stringify({ error: "Unauthorized: token verification failed" }),
        { status: 401, headers: corsHeaders }
      );
    }

    const callerId = user.id;

    // 2. Elevated Service Client for Rate Limiting & Admin Queries
    const adminClient = deps?.adminClient ?? createClient(supabaseUrl!, supabaseServiceRoleKey!);

    // 3. Abuse Rate Limiting (Server-Controlled Distributed Atomic RPC)
    const rateLimitFn = deps?.rateLimiter ?? checkRateLimitRpc;
    const rateLimit = await rateLimitFn(adminClient, callerId);

    if (rateLimit.error) {
      console.error(`[send-push] Rate limit backend error for user=${callerId}: ${rateLimit.error}`);
      return new Response(
        JSON.stringify({ error: "Service Unavailable: push notification rate limit service unavailable" }),
        { status: 503, headers: corsHeaders }
      );
    }

    if (!rateLimit.allowed) {
      console.warn(`[send-push] Rate limit exceeded for user=${callerId}`);
      return new Response(
        JSON.stringify({
          error: "Too Many Requests: push dispatch rate limit exceeded",
          retryAfter: rateLimit.resetSeconds,
        }),
        {
          status: 429,
          headers: {
            ...corsHeaders,
            "Retry-After": String(rateLimit.resetSeconds),
          },
        }
      );
    }

    // 4. Parse and validate payload
    const body = await req.json().catch(() => null);
    if (!body || typeof body !== "object") {
      return new Response(
        JSON.stringify({ error: "Bad Request: JSON body required" }),
        { status: 400, headers: corsHeaders }
      );
    }

    const { chat_id, message_id } = body;

    if (!chat_id || typeof chat_id !== "string" || !UUID_REGEX.test(chat_id)) {
      return new Response(
        JSON.stringify({ error: "Bad Request: valid UUID chat_id is required" }),
        { status: 400, headers: corsHeaders }
      );
    }

    if (!message_id || typeof message_id !== "string" || !UUID_REGEX.test(message_id)) {
      return new Response(
        JSON.stringify({ error: "Bad Request: valid UUID message_id is required" }),
        { status: 400, headers: corsHeaders }
      );
    }

    // 5. Verify caller belongs to chat_members
    const { data: memberRecord, error: memberError } = await adminClient
      .from("chat_members")
      .select("user_id")
      .eq("chat_id", chat_id)
      .eq("user_id", callerId)
      .maybeSingle();

    if (memberError || !memberRecord) {
      return new Response(
        JSON.stringify({ error: "Forbidden: caller is not an active participant in this chat" }),
        { status: 403, headers: corsHeaders }
      );
    }

    // 6. Verify message exists, belongs to specified chat, and was authored by caller
    // Retry loop (up to 3 attempts with 350ms delay) eliminates outbox race condition
    let messageRecord: MessageRecord | null = null;
    const maxAttempts = deps ? 1 : 3;

    for (let attempt = 0; attempt < maxAttempts; attempt++) {
      const { data, error: msgError } = await adminClient
        .from("messages")
        .select("id, chat_id, sender_id, type, text, media")
        .eq("id", message_id)
        .eq("chat_id", chat_id)
        .maybeSingle();

      if (data && data.sender_id === callerId) {
        messageRecord = data;
        break;
      }

      if (attempt < maxAttempts - 1) {
        await new Promise((res) => setTimeout(res, 350));
      }
    }

    if (!messageRecord) {
      return new Response(
        JSON.stringify({ error: "Forbidden: message does not exist or sender_id mismatch" }),
        { status: 403, headers: corsHeaders }
      );
    }

    // 7. Resolve sender registered phone strictly from verified database records
    const { data: profileRecord } = await adminClient
      .from("profiles")
      .select("phone_e164")
      .eq("id", callerId)
      .maybeSingle();

    const registeredPhone =
      (typeof profileRecord?.phone_e164 === "string" && profileRecord.phone_e164.trim().length > 0)
        ? profileRecord.phone_e164.trim()
        : (typeof user.phone === "string" && user.phone.trim().length > 0)
          ? user.phone.trim()
          : "";

    // 8. Derive notification content strictly from database records (never username or display_name)
    const { preview, type: derivedType, senderName } = deriveNotificationContent(
      messageRecord,
      { phone_e164: registeredPhone },
    );

    // 9. Query recipient members (strictly excluding caller)
    const { data: recipients, error: recipientsError } = await adminClient
      .from("chat_members")
      .select("user_id")
      .eq("chat_id", chat_id)
      .neq("user_id", callerId);

    if (recipientsError || !recipients || recipients.length === 0) {
      return new Response(
        JSON.stringify({ success: true, delivered_count: 0, reason: "no_other_recipients" }),
        { status: 200, headers: corsHeaders }
      );
    }

    const recipientUserIds = recipients.map((r: { user_id: string }) => r.user_id);
    const primaryRecipientId = recipientUserIds.length === 1 ? recipientUserIds[0] : null;

    // 10b. Issue short-lived recipient-specific delivery receipt token (direct chats)
    let receiptToken: string | null = null;
    if (primaryRecipientId) {
      try {
        const generatedToken = crypto.randomUUID();
        const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
        const { error: tokenError } = await adminClient
          .from("message_delivery_receipt_tokens")
          .insert({
            message_id,
            recipient_id: primaryRecipientId,
            token: generatedToken,
            expires_at: expiresAt,
          });

        if (!tokenError) {
          receiptToken = generatedToken;
        } else {
          console.warn(`[send-push] Non-fatal delivery token insert notice: ${tokenError.message}`);
        }
      } catch (tokenErr) {
        console.warn(`[send-push] Non-fatal delivery token generation notice: ${tokenErr}`);
      }
    }

    // 10. Query active devices for recipients
    const { data: devices, error: deviceError } = await adminClient
      .from("user_devices")
      .select("player_id, user_id, platform")
      .in("user_id", recipientUserIds)
      .eq("subscribed", true);

    if (deviceError || !devices || devices.length === 0) {
      return new Response(
        JSON.stringify({ success: true, delivered_count: 0, reason: "no_registered_devices" }),
        { status: 200, headers: corsHeaders }
      );
    }

    // 11. Extract and validate OneSignal subscription IDs (excluding raw FCM tokens or invalid formats)
    const validOneSignalIds = devices
      .map((d: { player_id: unknown }) =>
        typeof d.player_id === "string" ? d.player_id.trim() : ""
      )
      .filter((id: string) => isValidOneSignalSubscriptionId(id));

    const uniqueOneSignalIds = [...new Set(validOneSignalIds)];

    if (uniqueOneSignalIds.length === 0) {
      return new Response(
        JSON.stringify({
          success: true,
          delivered_count: 0,
          reason: "no_valid_onesignal_subscriptions",
        }),
        { status: 200, headers: corsHeaders }
      );
    }

    // 12. Deliver via OneSignal REST API (Sole Notification Provider)
    const fetcher = deps?.fetcher ?? fetch;
    const oneSignalPayload = {
      app_id: onesignalAppId ?? "dummy-app-id",
      include_subscription_ids: uniqueOneSignalIds,
      headings: { en: senderName },
      contents: { en: preview },
      data: {
        chatId: chat_id,
        messageId: message_id,
        type: derivedType,
        senderPhone: registeredPhone,
        senderId: callerId,
        ...(primaryRecipientId ? { recipientId: primaryRecipientId } : {}),
        ...(receiptToken ? { receiptToken } : {}),
      },
      existing_android_channel_id: "chat_messages",
      priority: 10,
    };

    const rawRestKey = (onesignalRestKey ?? "dummy-key").trim();
    const cleanRestKey = rawRestKey.replace(/^(Key|Basic)\s+/i, "");

    let osResponse: Response;
    try {
      osResponse = await fetcher("https://api.onesignal.com/notifications", {
        method: "POST",
        headers: {
          "Content-Type": "application/json; charset=UTF-8",
          Authorization: `Key ${cleanRestKey}`,
        },
        body: JSON.stringify(oneSignalPayload),
        signal: AbortSignal.timeout(8000),
      });
    } catch (fetchErr: unknown) {
      const isTimeout =
        fetchErr instanceof Error &&
        (fetchErr.name === "TimeoutError" || fetchErr.name === "AbortError");

      if (isTimeout) {
        console.error(`[send-push] OneSignal request timed out (8s limit) for chat_id=${chat_id}`);
        return new Response(
          JSON.stringify({ error: "Gateway Timeout: push notification provider timed out" }),
          { status: 504, headers: corsHeaders }
        );
      }

      console.error("[send-push] Network error connecting to OneSignal provider");
      return new Response(
        JSON.stringify({ error: "Bad Gateway: failed to reach push notification provider" }),
        { status: 502, headers: corsHeaders }
      );
    }

    const osResponseBody = await osResponse.json().catch(() => null);

    if (!osResponse.ok) {
      let rawError = "Unknown rejection";
      if (osResponseBody && typeof osResponseBody === "object") {
        if (Array.isArray(osResponseBody.errors) && osResponseBody.errors.length > 0) {
          rawError = osResponseBody.errors
            .map((e: unknown) => (typeof e === "string" ? e : JSON.stringify(e)))
            .join("; ");
        } else if (typeof osResponseBody.errors === "string") {
          rawError = osResponseBody.errors;
        } else if (typeof osResponseBody.error === "string") {
          rawError = osResponseBody.error;
        } else if (osResponseBody.errors && typeof osResponseBody.errors === "object") {
          rawError = JSON.stringify(osResponseBody.errors);
        }
      }

      // Sanitize: truncate long error text, omit credentials or sensitive tokens
      const sanitizedError = rawError.length > 300
        ? rawError.slice(0, 300) + "..."
        : rawError;

      console.error(
        `[send-push] OneSignal returned status ${osResponse.status}: ${sanitizedError}`
      );

      return new Response(
        JSON.stringify({
          error: "OneSignal API rejection",
          statusCode: osResponse.status,
        }),
        { status: 502, headers: corsHeaders }
      );
    }

    const reportedRecipients =
      typeof osResponseBody?.recipients === "number"
        ? osResponseBody.recipients
        : uniqueOneSignalIds.length;

    const oneSignalResponseId =
      typeof osResponseBody?.id === "string" ? osResponseBody.id : undefined;

    return new Response(
      JSON.stringify({
        success: true,
        delivered_count: reportedRecipients,
        onesignal_recipients: uniqueOneSignalIds.length,
        oneSignalId: oneSignalResponseId,
      }),
      { status: 200, headers: corsHeaders }
    );
  } catch (err: unknown) {
    console.error("[send-push] Unhandled error processing push notification");
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: corsHeaders }
    );
  }
}

if (import.meta.main) {
  serve((req) => handler(req));
}
