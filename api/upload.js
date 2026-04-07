import { kv } from "@vercel/kv";

function makeId() {
  return crypto.randomUUID().replace(/-/g, "").slice(0, 16);
}

function getBaseUrl(req) {
  const host = req.headers["x-forwarded-host"] || req.headers.host || "localhost";
  const proto = req.headers["x-forwarded-proto"] || "https";
  return `${proto}://${host}`;
}

async function handlePost(req, res) {
  let data = req.body;

  if (typeof data === "string") {
    try {
      data = JSON.parse(data);
    } catch {
      return res.status(400).json({ error: "Invalid JSON body" });
    }
  }

  if (!data || typeof data !== "object" || Array.isArray(data)) {
    return res.status(400).json({ error: "Body must be a JSON object" });
  }

  const id = makeId();
  await kv.set(`result:${id}`, data, { ex: 60 * 60 * 24 * 7 });

  return res.status(200).json({ url: `${getBaseUrl(req)}/view.html?id=${id}`, id });
}

async function handleGet(req, res) {
  const action = typeof req.query.action === "string" ? req.query.action : "";

  if (action === "init") {
    const id = makeId();
    await kv.set(`upload:${id}:buf`, "", { ex: 60 * 60 });
    return res.status(200).json({ id });
  }

  if (action === "chunk") {
    const id = typeof req.query.id === "string" ? req.query.id.toLowerCase() : "";
    const data = typeof req.query.data === "string" ? req.query.data : "";

    if (!/^[a-f0-9]{16}$/i.test(id)) {
      return res.status(400).json({ error: "Invalid or missing id" });
    }

    if (data === "") {
      return res.status(400).json({ error: "Missing chunk data" });
    }

    const key = `upload:${id}:buf`;
    const current = await kv.get(key);
    const existing = typeof current === "string" ? current : "";
    await kv.set(key, existing + data, { ex: 60 * 60 });

    return res.status(200).json({ ok: true });
  }

  if (action === "finalize") {
    const id = typeof req.query.id === "string" ? req.query.id.toLowerCase() : "";

    if (!/^[a-f0-9]{16}$/i.test(id)) {
      return res.status(400).json({ error: "Invalid or missing id" });
    }

    const key = `upload:${id}:buf`;
    const raw = await kv.get(key);

    if (typeof raw !== "string" || raw === "") {
      return res.status(404).json({ error: "Upload buffer not found or empty" });
    }

    let data;
    try {
      data = JSON.parse(raw);
    } catch {
      return res.status(400).json({ error: "Buffered upload was not valid JSON" });
    }

    if (!data || typeof data !== "object" || Array.isArray(data)) {
      return res.status(400).json({ error: "Buffered upload did not decode to a JSON object" });
    }

    await kv.set(`result:${id}`, data, { ex: 60 * 60 * 24 * 7 });
    await kv.del(key);

    return res.status(200).json({ url: `${getBaseUrl(req)}/view.html?id=${id}`, id });
  }

  return res.status(405).json({
    error: "Method Not Allowed",
    hint: "Use POST for normal uploads, or GET with action=init|chunk|finalize for fallback uploads."
  });
}

export default async function handler(req, res) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Expect");

  if (req.method === "OPTIONS") return res.status(200).end();

  try {
    if (req.method === "POST") {
      return await handlePost(req, res);
    }

    if (req.method === "GET") {
      return await handleGet(req, res);
    }

    return res.status(405).json({ error: "Method Not Allowed" });
  } catch (err) {
    console.error("[upload] error:", err);
    return res.status(500).json({
      error: "Internal server error",
      hint: "Make sure Vercel KV is connected and environment variables are available in this deployment."
    });
  }
}
