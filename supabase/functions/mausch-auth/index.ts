import { createClient } from "@supabase/supabase-js";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const publicKey = "sb_publishable_0EUlVHlrWJCZ9t945DUcrw_KXzGcCdT";
const admin = createClient(supabaseUrl, serviceKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});
const publicAuth = createClient(supabaseUrl, publicKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const allowedOrigins = new Set(["https://ppt0320.github.io"]);
const corsHeaders = (origin: string | null) => ({
  "Access-Control-Allow-Origin": origin && allowedOrigins.has(origin) ? origin : "https://ppt0320.github.io",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
});

function response(body: unknown, status: number, origin: string | null) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(origin), "Content-Type": "application/json; charset=utf-8" },
  });
}

function normalizeUsername(value: unknown): string {
  const username = typeof value === "string" ? value.trim().toLowerCase() : "";
  if (!/^[a-z0-9._-]{3,24}$/.test(username)) {
    throw new Error("El ID debe tener entre 3 y 24 caracteres: letras, números, punto, guion o guion bajo.");
  }
  return username;
}

function validatePassword(value: unknown): string {
  if (typeof value !== "string" || value.length < 12 || value.length > 128) {
    throw new Error("La contraseña debe tener entre 12 y 128 caracteres.");
  }
  return value;
}

function normalizeRecovery(value: unknown): string {
  return typeof value === "string" ? value.toLowerCase().replace(/[^a-f0-9]/g, "") : "";
}

function randomHex(byteCount: number): string {
  const bytes = crypto.getRandomValues(new Uint8Array(byteCount));
  return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function formatRecovery(raw: string): string {
  return raw.match(/.{1,8}/g)!.join("-").toUpperCase();
}

async function hash(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function allowRequest(request: Request, action: string, maxRequests: number, windowSeconds: number) {
  const forwarded = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  const clientIp = forwarded || request.headers.get("cf-connecting-ip") || "unknown";
  const bucketHash = await hash(`${action}:${clientIp}`);
  const { data, error } = await admin.rpc("mausch_consume_auth_limit", {
    p_bucket_hash: bucketHash,
    p_max_requests: maxRequests,
    p_window_seconds: windowSeconds,
  });
  if (error) throw new Error("No se pudo validar el límite de solicitudes.");
  return data === true;
}

async function internalEmail(username: string): Promise<string> {
  return `id-${await hash(username)}@accounts.mausch.invalid`;
}

async function findIdentity(column: "username" | "user_id", value: string) {
  const result = await admin.from("mausch_identities").select("user_id,username,recovery_code_hash").eq(column, value).maybeSingle();
  if (result.error) throw new Error("No se pudo consultar la cuenta.");
  return result.data;
}

async function currentUser(authorization: string | null) {
  const token = authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) return null;
  const { data, error } = await publicAuth.auth.getUser(token);
  return error ? null : data.user;
}

async function setPassword(userId: string, password: string) {
  const { error } = await admin.auth.admin.updateUserById(userId, { password });
  if (error) throw new Error("No se pudo actualizar la contraseña.");
}

async function linkPassword(userId: string, username: string, password: string) {
  const { error } = await admin.auth.admin.updateUserById(userId, {
    email: await internalEmail(username),
    email_confirm: true,
    password,
  });
  if (error) throw new Error("No se pudo actualizar la contraseña.");
}

async function createUser(email: string, password: string) {
  const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
  if (error || !data.user) throw new Error("No se pudo crear la cuenta. Revisa si el ID ya está ocupado.");
  return data.user;
}

async function deleteUser(userId: string) {
  await admin.auth.admin.deleteUser(userId);
}

async function issueSession(username: string, password: string) {
  const email = await internalEmail(username);
  const { data, error } = await publicAuth.auth.signInWithPassword({ email, password });
  if (error || !data.session) return null;
  return {
    access_token: data.session.access_token,
    refresh_token: data.session.refresh_token,
    expires_in: data.session.expires_in,
    token_type: data.session.token_type,
    user: { id: data.user.id },
  };
}

async function storeIdentity(userId: string, username: string, recoveryHash: string) {
  const { error } = await admin.from("mausch_identities").upsert({
    user_id: userId,
    username,
    recovery_code_hash: recoveryHash,
    recovery_attempts: 0,
    recovery_locked_until: null,
    updated_at: new Date().toISOString(),
  }, { onConflict: "user_id" });
  if (error) throw new Error("Ese ID ya está en uso o no se pudo guardar.");
}

Deno.serve(async (request: Request) => {
  const origin = request.headers.get("origin");
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(origin) });
  if (request.method !== "POST") return response({ message: "Método no permitido." }, 405, origin);

  try {
    const body = await request.json();
    const action = body?.action;

    if (action === "status") {
      const user = await currentUser(request.headers.get("authorization"));
      if (!user) return response({ linked: false }, 200, origin);
      const identity = await findIdentity("user_id", user.id);
      return response({ linked: !!identity, username: identity?.username ?? null }, 200, origin);
    }

    if (action === "login") {
      const username = normalizeUsername(body.username);
      const password = validatePassword(body.password);
      if (!await allowRequest(request, "login", 24, 600)) return response({ message: "Demasiados intentos. Espera unos minutos y vuelve a probar." }, 429, origin);
      const identity = await findIdentity("username", username);
      // Run the same Auth password verification for unknown IDs to reduce timing-based enumeration.
      const session = await issueSession(username, password);
      if (!identity || !session || session.user.id !== identity.user_id) {
        return response({ message: "ID o contraseña incorrectos." }, 401, origin);
      }
      return response({ session, username: identity.username }, 200, origin);
    }

    if (action === "register") {
      const username = normalizeUsername(body.username);
      const password = validatePassword(body.password);
      if (!await allowRequest(request, "register", 5, 3600)) return response({ message: "Por ahora no se pueden crear más cuentas desde esta conexión. Intenta más tarde." }, 429, origin);
      if (await findIdentity("username", username)) return response({ message: "Ese ID ya está ocupado." }, 409, origin);
      const rawCode = randomHex(24);
      const email = await internalEmail(username);
      const user = await createUser(email, password);
      try {
        await storeIdentity(user.id, username, await hash(rawCode));
      } catch (error) {
        await deleteUser(user.id);
        throw error;
      }
      const session = await issueSession(username, password);
      if (!session) return response({ message: "La cuenta quedó creada. Inicia sesión con tu ID y contraseña.", recoveryCode: formatRecovery(rawCode) }, 201, origin);
      return response({ session, username, recoveryCode: formatRecovery(rawCode) }, 201, origin);
    }

    if (action === "link") {
      const user = await currentUser(request.headers.get("authorization"));
      if (!user) return response({ message: "Inicia la sesión actual de tu cuenta para conservar tus datos." }, 401, origin);
      const username = normalizeUsername(body.username);
      const password = validatePassword(body.password);
      const existing = await findIdentity("user_id", user.id);
      if (existing) return response({ message: "Esta cuenta ya tiene un ID vinculado." }, 409, origin);
      const code = randomHex(24);
      if (await findIdentity("username", username)) return response({ message: "Ese ID ya está ocupado." }, 409, origin);
      await storeIdentity(user.id, username, await hash(code));
      try {
        await linkPassword(user.id, username, password);
      } catch (error) {
        await admin.from("mausch_identities").delete().eq("user_id", user.id);
        throw error;
      }
      return response({ linked: true, username, recoveryCode: formatRecovery(code) }, 200, origin);
    }

    if (action === "recover") {
      const username = normalizeUsername(body.username);
      const password = validatePassword(body.password);
      if (!await allowRequest(request, "recover", 8, 900)) return response({ message: "Demasiados intentos. Espera unos minutos y vuelve a probar." }, 429, origin);
      const recovery = normalizeRecovery(body.recoveryCode);
      if (!/^[a-f0-9]{48}$/.test(recovery)) return response({ message: "ID o código incorrectos." }, 401, origin);
      const identity = await findIdentity("username", username);
      if (!identity) return response({ message: "ID o código incorrectos." }, 401, origin);
      const nextCode = randomHex(24);
      const { data, error } = await admin.rpc("mausch_consume_recovery_code", {
        p_user_id: identity.user_id,
        p_code_hash: await hash(recovery),
        p_next_hash: await hash(nextCode),
      });
      if (error || data !== true) return response({ message: "ID o código incorrectos, o el código está temporalmente bloqueado." }, 401, origin);
      try {
        await setPassword(identity.user_id, password);
      } catch {
        return response({ message: "No se pudo cambiar la contraseña. Guarda este nuevo código de recuperación y vuelve a intentarlo.", recoveryCode: formatRecovery(nextCode) }, 502, origin);
      }
      return response({ recovered: true, recoveryCode: formatRecovery(nextCode) }, 200, origin);
    }

    return response({ message: "Solicitud no válida." }, 400, origin);
  } catch (error) {
    const message = error instanceof Error ? error.message : "No se pudo completar la solicitud.";
    return response({ message }, 400, origin);
  }
});
